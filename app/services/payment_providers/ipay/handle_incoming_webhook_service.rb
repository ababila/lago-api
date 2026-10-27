# frozen_string_literal: true

module PaymentProviders
  module Ipay
    # i-pay proves a webhook with a static shared secret, and never retries a delivery that failed.
    # So a webhook only triggers a read of the link it names; polling settles the payment otherwise.
    class HandleIncomingWebhookService < BaseService
      Result = BaseResult

      def initialize(organization_id:, body:, secret:, code: nil)
        @organization_id = organization_id
        @body = body
        @secret = secret
        @code = code

        super
      end

      def call
        payment_provider_result = PaymentProviders::FindService.call(
          organization_id:,
          code:,
          payment_provider_type: "ipay"
        )
        return payment_provider_result unless payment_provider_result.success?

        @payment_provider = payment_provider_result.payment_provider

        webhook_secret = payment_provider.webhook_secret
        return result.service_failure!(code: "webhook_error", message: "Webhook secret is missing") if webhook_secret.blank?

        unless ActiveSupport::SecurityUtils.secure_compare(webhook_secret, secret.to_s)
          return result.service_failure!(code: "webhook_error", message: "Invalid webhook secret")
        end

        data = payload_data
        return result.service_failure!(code: "webhook_error", message: "Invalid payload") unless data

        # The payload also carries the payer's phone number and name: only these fields are read.
        status = data["status"].to_s
        payment_intent = find_payment_intent(data["external_payment_reference"])
        Rails.logger.info("[i-pay] webhook status=#{status} payment_intent_id=#{payment_intent&.id || "unmatched"}")

        if status == "refunded"
          Rails.logger.error("[i-pay] payment refunded payment_intent_id=#{payment_intent&.id || "unmatched"}")
        end

        PaymentProviders::Ipay::PaymentIntents::RefreshJob.perform_later(payment_intent) if payment_intent
        PaymentProviders::Ipay::PaymentIntents::RearmPollsJob.perform_later(payment_provider.organization)

        result
      end

      private

      attr_reader :organization_id, :body, :secret, :code, :payment_provider

      def payload_data
        data = JSON.parse(body.to_s)
        data["data"] if data.is_a?(Hash) && data["data"].is_a?(Hash)
      rescue JSON::ParserError
        nil
      end

      def find_payment_intent(reference)
        return if !reference.is_a?(String) || reference.blank?

        PaymentIntent.where(organization_id: payment_provider.organization_id).find_by(provider_session_id: reference)
      end
    end
  end
end
