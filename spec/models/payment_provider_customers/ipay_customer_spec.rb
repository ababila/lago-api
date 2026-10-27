# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::IpayCustomer do
  subject(:ipay_customer) { build(:ipay_customer) }

  describe "#require_provider_payment_id?" do
    it "returns false, as i-pay has no customer object" do
      expect(ipay_customer.require_provider_payment_id?).to be(false)
    end
  end
end
