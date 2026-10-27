# frozen_string_literal: true

module Invoices
  module Payments
    class IpayService < BaseService
      include Customers::PaymentProviderFinder
      include TypedResults

      PROVIDER_NAME = "i-pay"

      RESULTS = {
        update_payment_status: BaseResult[:payment, :invoice],
        generate_payment_url: BaseResult[:payment_url, :provider_session_id],
        expire_payment_url: BaseResult
      }.freeze

      private

      attr_accessor :invoice

      delegate :customer, to: :invoice

      # Records a payment that i-pay reports as succeeded on one of the invoice's links.
      # A payment that cannot settle the invoice is still recorded, without a payable payment status,
      # so that no money i-pay collected is dropped.
      def update_payment_status(invoice:, provider_payment_id:, amount_cents:, currency:)
        @invoice = invoice
        result.invoice = invoice

        ActiveRecord::Base.transaction do
          # Serializes the webhook refresh and the poll of the same invoice.
          invoice.lock!

          payment = Payment.where(organization_id: invoice.organization_id)
            .find_by(payment_provider_id: ipay_customer&.payment_provider_id, provider_payment_id:)
          if payment
            result.payment = payment
          else
            record_payment(provider_payment_id:, amount_cents:, currency:)
          end
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      def generate_payment_url(invoice, payment_intent)
        @invoice = invoice

        if invoice.currency != ::PaymentProviders::IpayProvider::CURRENCY
          return result.single_validation_failure!(field: :currency, error_code: "value_is_invalid")
        end

        amount = Money.from_cents(invoice.total_due_amount_cents, invoice.currency).to_d
        if amount < ::PaymentProviders::IpayProvider::MINIMUM_AMOUNT || amount.frac.nonzero?
          return result.single_validation_failure!(field: :total_due_amount_cents, error_code: "invalid_amount")
        end

        # The reference is the only key to read the link's result, and that read needs no API key.
        # It is random, stored before the link exists, and never logged.
        reference = SecureRandom.hex(16)
        payment_intent.update!(
          provider_session_id: reference,
          expires_at: ::PaymentProviders::IpayProvider::PAYMENT_INTENT_TTL.from_now
        )

        response = http_client.post_with_response(link_params(reference, amount.to_i), link_headers)
        page_url = JSON.parse(response.body)["page_url"]

        after_commit { ::PaymentProviders::Ipay::PaymentIntents::PollJob.set(wait: 1.minute).perform_later(payment_intent) }
        ::PaymentProviders::Ipay::PaymentIntents::RearmPollsJob.perform_after_commit(invoice.organization)
        Rails.logger.info("[i-pay] link created payment_intent_id=#{payment_intent.id} invoice_id=#{invoice.id}")

        result.payment_url = page_url
        result.provider_session_id = reference
        result
      rescue LagoHttpClient::HttpError => e
        result.third_party_failure!(third_party: PROVIDER_NAME, error_code: e.error_code, error_message: e.error_body)
      rescue JSON::ParserError, *::PaymentProviders::IpayProvider::NETWORK_ERRORS => e
        result.third_party_failure!(third_party: PROVIDER_NAME, error_code: e.class.name, error_message: e.message)
      end

      # i-pay has no API to cancel a link: it dies 30 minutes after creation, and is polled until then.
      def expire_payment_url(_invoice, _payment_intent)
        result
      end

      def record_payment(provider_payment_id:, amount_cents:, currency:)
        held_reason = held_reason(amount_cents:, currency:)

        payment = Payment.create!(
          organization_id: invoice.organization_id,
          payable: invoice,
          customer:,
          payment_provider_id: ipay_customer&.payment_provider_id,
          payment_provider_customer: ipay_customer,
          amount_cents: amount_cents || 0,
          amount_currency: invoice.currency,
          provider_payment_id:,
          status: "succeeded",
          payable_payment_status: held_reason ? nil : :succeeded,
          error_code: held_reason
        )
        result.payment = payment

        if held_reason
          Rails.logger.error(
            "[i-pay] payment held reason=#{held_reason} payment_id=#{payment.id} invoice_id=#{invoice.id}"
          )
          return
        end

        invoice.update!(payment_attempts: invoice.payment_attempts + 1)
        Invoices::UpdateService.call!(
          invoice:,
          params: {
            payment_status: :succeeded,
            ready_for_payment_processing: false,
            total_paid_amount_cents: invoice.payments.where(payable_payment_status: :succeeded).sum(:amount_cents)
          },
          webhook_notification: true
        )
        SendWebhookJob.perform_after_commit("payment.succeeded", payment)
        Rails.logger.info("[i-pay] payment settled payment_id=#{payment.id} invoice_id=#{invoice.id}")
      end

      def held_reason(amount_cents:, currency:)
        return "ipay_invoice_already_paid" if invoice.payment_succeeded?
        return "ipay_currency_mismatch" if currency.to_s.upcase != invoice.currency
        return "ipay_amount_mismatch" if amount_cents != expected_amount_cents

        nil
      end

      # A voided invoice has nothing due, yet a payment that lands after the void still settles it,
      # as it does with the other providers. So the void is ignored here.
      def expected_amount_cents
        invoice.total_amount_cents - invoice.total_paid_amount_cents - invoice.offset_amount_cents
      end

      def link_params(reference, amount)
        {
          title: "#{invoice.billing_entity.name} - Invoice #{invoice.number}",
          amount:,
          reference:,
          on_success_redirection_url: ipay_payment_provider.success_redirect_url.presence,
          on_failed_redirection_url: ipay_payment_provider.success_redirect_url.presence
        }.compact
      end

      def link_headers
        ipay_payment_provider.api_headers.merge("Ipay-Payment-Type" => "external_payment")
      end

      def ipay_payment_provider
        @ipay_payment_provider ||= payment_provider(customer)
      end

      # The customer may have moved to another provider since the link was created.
      def ipay_customer
        @ipay_customer ||= customer.ipay_customer
      end

      def http_client
        @http_client ||= LagoHttpClient::Client.new("#{ipay_payment_provider.api_url}/external_payments")
      end
    end
  end
end
