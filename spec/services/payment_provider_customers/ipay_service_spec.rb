# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::IpayService do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization: organization) }
  let(:ipay_provider) { create(:ipay_provider, organization: organization) }
  let(:ipay_customer) { create(:ipay_customer, customer: customer, payment_provider: ipay_provider) }

  describe ".call(:create)" do
    it "returns success with the ipay customer" do
      result = described_class.call(:create, ipay_customer)

      expect(result).to be_success
      expect(result.ipay_customer).to eq(ipay_customer)
    end
  end

  describe ".call(:update)" do
    it "returns success" do
      result = described_class.call(:update, ipay_customer)

      expect(result).to be_success
    end
  end

  describe ".call(:generate_checkout_url)" do
    it "returns not allowed failure" do
      result = described_class.call(:generate_checkout_url, ipay_customer)

      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      expect(result.error.code).to eq("feature_not_supported")
    end

    context "when send_webhook is false" do
      it "returns not allowed failure" do
        result = described_class.call(:generate_checkout_url, ipay_customer, send_webhook: false)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("feature_not_supported")
      end
    end
  end

  describe "private methods" do
    describe "#customer" do
      it "delegates to ipay_customer" do
        service = described_class.new
        service.instance_variable_set(:@ipay_customer, ipay_customer)

        expect(service.send(:customer)).to eq(customer)
      end
    end
  end
end
