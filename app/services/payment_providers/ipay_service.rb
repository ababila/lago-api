# frozen_string_literal: true

module PaymentProviders
  class IpayService < BaseService
    Result = BaseResult[:ipay_provider]

    def create_or_update(**args)
      payment_provider_result = PaymentProviders::FindService.call(
        organization_id: args[:organization].id,
        code: args[:code],
        id: args[:id],
        payment_provider_type: "ipay"
      )

      ipay_provider = if payment_provider_result.success?
        payment_provider_result.payment_provider
      else
        PaymentProviders::IpayProvider.new(
          organization_id: args[:organization].id,
          code: args[:code]
        )
      end

      old_code = ipay_provider.code

      ipay_provider.secret_key = args[:secret_key] if args.key?(:secret_key) && !Types::ObfuscatedStringType.obfuscated?(args[:secret_key])
      ipay_provider.success_redirect_url = args[:success_redirect_url] if args.key?(:success_redirect_url)
      ipay_provider.code = args[:code] if args.key?(:code)
      ipay_provider.name = args[:name] if args.key?(:name)
      ipay_provider.save!
      if payment_provider_code_changed?(ipay_provider, old_code, args)
        ipay_provider.customers.update_all(payment_provider_code: args[:code]) # rubocop:disable Rails/SkipsModelValidations
      end

      result.ipay_provider = ipay_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
