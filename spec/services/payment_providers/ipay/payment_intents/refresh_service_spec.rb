# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Ipay::PaymentIntents::RefreshService do
  subject(:result) { described_class.call(payment_intent:) }

  let(:organization) { create(:organization) }
  let(:ipay_provider) { create(:ipay_provider, organization:) }
  let(:customer) { create(:customer, organization:, payment_provider: "ipay", payment_provider_code: ipay_provider.code) }
  let(:invoice) { create(:invoice, organization:, customer:, currency: "XOF", total_amount_cents: 1500) }
  let(:reference) { SecureRandom.hex(16) }
  let(:payment_intent) { create(:payment_intent, invoice:, provider_session_id: reference) }
  let(:link_url) { "https://i-pay.money/api/v1/external_payments/#{reference}" }

  before do
    create(:ipay_customer, customer:, payment_provider: ipay_provider)
    stub_request(:get, link_url).to_return(status: 200, body: link.to_json)
  end

  context "when a payment succeeded on the link" do
    let(:link) do
      {
        reference:,
        amount: 1500,
        country: "NE",
        currency: "XOF",
        transaction_id: "txn_1",
        msisdn: "22790000000",
        customer_name: "Payer Name",
        status: "succeeded",
        created_at: "2026-10-27T10:00:00.000+01:00"
      }
    end

    it "records the payment from the link read" do
      expect(result).to be_success
      expect(result.link_status).to eq("succeeded")
      expect(result.payment).to have_attributes(provider_payment_id: "txn_1", amount_cents: 1500)
      expect(invoice.reload.payment_status).to eq("succeeded")
    end

    it "keeps none of the payer details" do
      expect(result.payment.provider_payment_data).to be_blank
      expect(result.payment.provider_payment_method_data).to be_blank
    end
  end

  context "when the amount is a decimal string" do
    let(:link) { {reference:, status: "succeeded", transaction_id: "txn_1", amount: "1500.0", currency: "xof"} }

    it "reads it as the amount due" do
      expect(result.payment).to have_attributes(amount_cents: 1500, payable_payment_status: "succeeded")
    end
  end

  context "when the succeeded link has no transaction" do
    let(:link) { {reference:, status: "succeeded", amount: 1500, currency: "XOF"} }

    it "records nothing" do
      expect(result).to be_success
      expect(result.payment).to be_nil
      expect(invoice.reload.payment_status).to eq("pending")
    end
  end

  context "when the link is waiting for a payment" do
    let(:link) { {message: "Waiting", status: "initiated", reference:, page_url: "https://i-pay.money/x"} }

    it "records nothing" do
      expect(result).to be_success
      expect(result.link_status).to eq("initiated")
      expect(result.payment).to be_nil
    end
  end

  context "when the last attempt failed" do
    let(:link) { {reference:, amount: 1500, currency: "XOF", transaction_id: "txn_1", status: "failed"} }

    it "neither records a payment nor fails the invoice" do
      expect(result).to be_success
      expect(result.link_status).to eq("failed")
      expect(Payment.count).to eq(0)
      expect(invoice.reload.payment_status).to eq("pending")
    end
  end

  context "when the link expired" do
    let(:link) { {message: "This payment link has expired", has_expire: true, status: "cancelled", reference:} }

    it "returns its status" do
      expect(result.link_status).to eq("cancelled")
    end
  end

  context "when i-pay does not know the link" do
    before { stub_request(:get, link_url).to_return(status: 404, body: {message: "Not found"}.to_json) }

    let(:link) { {} }

    it "returns not_found" do
      expect(result).to be_success
      expect(result.link_status).to eq("not_found")
    end
  end

  context "when i-pay answers with an error" do
    before { stub_request(:get, link_url).to_return(status: 500, body: "oops") }

    let(:link) { {} }

    it "fails without exposing the link URL" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("ipay_link_unreadable")
      expect(result.error.error_message).not_to include(reference)
    end
  end

  context "when i-pay answers with something else than an object" do
    before { stub_request(:get, link_url).to_return(status: 200, body: "[]") }

    let(:link) { {} }

    it "fails" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("ipay_link_unreadable")
    end
  end

  context "when i-pay cannot be reached" do
    before { stub_request(:get, link_url).to_raise(SocketError) }

    let(:link) { {} }

    it "fails" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("ipay_link_unreadable")
    end
  end

  context "when the intent has no link" do
    let(:payment_intent) { create(:payment_intent, invoice:, provider_session_id: nil) }
    let(:link) { {} }

    it "reads nothing" do
      expect(result).to be_success
      expect(result.link_status).to be_nil
      expect(WebMock).not_to have_requested(:get, /i-pay.money/)
    end
  end
end
