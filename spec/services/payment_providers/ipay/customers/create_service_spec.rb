# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Ipay::Customers::CreateService do
  subject(:result) { described_class.call(customer:, payment_provider_id: ipay_provider.id, params:) }

  let(:customer) { create(:customer) }
  let(:ipay_provider) { create(:ipay_provider, organization: customer.organization) }
  let(:params) { {} }

  it "links the customer to i-pay, with no customer on the i-pay side" do
    expect(result).to be_success
    expect(result.provider_customer).to have_attributes(
      customer_id: customer.id,
      payment_provider_id: ipay_provider.id,
      organization_id: customer.organization_id,
      provider_customer_id: nil
    )
  end

  context "when the customer is already linked" do
    let(:ipay_customer) { create(:ipay_customer, customer:, payment_provider: ipay_provider) }

    before { ipay_customer }

    it "returns the existing link" do
      expect { result }.not_to change(PaymentProviderCustomers::IpayCustomer, :count)
      expect(result.provider_customer.id).to eq(ipay_customer.id)
    end
  end
end
