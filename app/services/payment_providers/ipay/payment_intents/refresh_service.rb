# frozen_string_literal: true

module PaymentProviders
  module Ipay
    module PaymentIntents
      # Reads the result of the i-pay link behind a payment intent, and records a succeeded payment.
      # A webhook only names a link: this read is what Lago trusts, for the status, the amount and
      # the currency.
      class RefreshService < BaseService
        Result = BaseResult[:payment_intent, :link_status, :payment]

        LINK_NOT_FOUND = "not_found"

        def initialize(payment_intent:)
          @payment_intent = payment_intent

          super
        end

        def call
          result.payment_intent = payment_intent
          return result if payment_intent.provider_session_id.blank?

          link = read_link
          result.link_status = link ? link["status"].to_s : LINK_NOT_FOUND
          Rails.logger.info("[i-pay] link read payment_intent_id=#{payment_intent.id} status=#{result.link_status}")

          record_payment(link) if result.link_status == "succeeded"

          result
        rescue LagoHttpClient::HttpError => e
          # The error carries the link URL, which contains the reference: only its status code is kept.
          result.service_failure!(code: "ipay_link_unreadable", message: "i-pay answered HTTP #{e.error_code}")
        rescue JSON::ParserError, *::PaymentProviders::IpayProvider::NETWORK_ERRORS => e
          result.service_failure!(code: "ipay_link_unreadable", message: e.class.name)
        end

        private

        attr_reader :payment_intent

        delegate :invoice, to: :payment_intent

        # The read needs no API key, and returns the payer's phone number and name, which are dropped here.
        # Its URL holds the reference, so the request is kept out of traces.
        def read_link
          response = OpenTelemetry::Common::Utilities.untraced do
            LagoHttpClient::Client.new(link_url).get(
              headers: {"Content-Type" => "application/json", "Accept" => "application/json"}
            )
          end
          raise JSON::ParserError, "unexpected link read" unless response.is_a?(Hash)

          response.slice("status", "transaction_id", "amount", "currency")
        rescue LagoHttpClient::HttpError => e
          raise unless e.error_code.to_i == 404

          nil
        end

        def link_url
          "#{::PaymentProviders::IpayProvider::API_URL}/external_payments/#{ERB::Util.url_encode(payment_intent.provider_session_id)}"
        end

        def record_payment(link)
          transaction_id = link["transaction_id"].presence
          unless transaction_id
            Rails.logger.error("[i-pay] succeeded link without transaction payment_intent_id=#{payment_intent.id}")
            return
          end

          result.payment = Invoices::Payments::IpayService.call!(
            :update_payment_status,
            invoice:,
            provider_payment_id: transaction_id.to_s,
            amount_cents: amount_cents(link["amount"]),
            currency: link["currency"]
          ).payment
        end

        def amount_cents(amount)
          return unless amount.is_a?(Integer) || amount.to_s.match?(/\A\d+(\.\d+)?\z/)

          Money.from_amount(BigDecimal(amount.to_s), invoice.currency).cents
        end
      end
    end
  end
end
