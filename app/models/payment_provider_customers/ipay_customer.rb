# frozen_string_literal: true

module PaymentProviderCustomers
  class IpayCustomer < BaseCustomer
    def require_provider_payment_id?
      false
    end
  end
end
