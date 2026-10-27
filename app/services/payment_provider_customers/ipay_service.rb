# frozen_string_literal: true

module PaymentProviderCustomers
  class IpayService < BaseService
    include Customers::PaymentProviderFinder
    include TypedResults

    RESULTS = {
      create: BaseResult[:ipay_customer],
      update: BaseResult,
      generate_checkout_url: BaseResult
    }.freeze

    private

    def create(ipay_customer)
      @ipay_customer = ipay_customer
      result.ipay_customer = ipay_customer
      result
    end

    def update(ipay_customer)
      @ipay_customer = ipay_customer
      result
    end

    def generate_checkout_url(ipay_customer, send_webhook: true)
      @ipay_customer = ipay_customer
      result.not_allowed_failure!(code: "feature_not_supported")
    end

    attr_accessor :ipay_customer

    delegate :customer, to: :ipay_customer
  end
end
