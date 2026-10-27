# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Ipay::HandleIncomingWebhookService do
  subject(:result) { described_class.call(organization_id: organization.id, body:, secret:, code: ipay_provider.code) }

  let(:organization) { create(:organization) }
  let(:ipay_provider) { create(:ipay_provider, organization:, webhook_secret: "webhook_secret_hash") }
  let(:secret) { "webhook_secret_hash" }
  let(:customer) { create(:customer, organization:, payment_provider: "ipay") }
  let(:reference) { SecureRandom.hex(16) }
  let(:payment_intent) { create(:payment_intent, invoice: create(:invoice, organization:, customer:), provider_session_id: reference) }
  let(:body) { payload.to_json }
  let(:payload) do
    {
      data: {
        external_reference: "738092677033",
        reference: "xq7sm5hqakoh",
        status: "succeeded",
        msisdn: "22790000000",
        net_amount: 1485,
        amount: 1500,
        failure_reason: nil,
        customer_name: "Payer Name",
        payment_method: "mobile_money",
        validated_at: "2026-10-27T10:00:00.000Z",
        external_payment_reference: reference
      }
    }
  end

  before do
    payment_intent
    ipay_provider
  end

  it "refreshes the link the webhook names" do
    expect { result }.to have_enqueued_job(PaymentProviders::Ipay::PaymentIntents::RefreshJob).with(payment_intent)
    expect(result).to be_success
  end

  it "re-arms the polling of the organization's links" do
    expect { result }.to have_enqueued_job(PaymentProviders::Ipay::PaymentIntents::RearmPollsJob).with(organization)
  end

  context "when the payment was refunded" do
    let(:payload) { {data: {reference: "xq7sm5hqakoh", status: "refunded", external_payment_reference: reference}} }

    it "logs an error, as refunds are made outside Lago" do
      allow(Rails.logger).to receive(:error)

      result

      expect(Rails.logger).to have_received(:error).with("[i-pay] payment refunded payment_intent_id=#{payment_intent.id}")
    end
  end

  it "enqueues none of the payer details" do
    result

    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.to_json).not_to include("22790000000", "Payer Name")
  end

  context "when the webhook names no known link" do
    let(:payload) { {data: {reference: "xq7sm5hqakoh", status: "succeeded", external_payment_reference: "unknown"}} }

    it "re-arms the polling of the organization's links" do
      expect { result }.to have_enqueued_job(PaymentProviders::Ipay::PaymentIntents::RearmPollsJob).with(organization)
      expect(result).to be_success
    end
  end

  context "when the link belongs to another organization" do
    let(:other_organization) { create(:organization) }
    let(:payment_intent) do
      other_customer = create(:customer, organization: other_organization, payment_provider: "ipay")
      create(:payment_intent, invoice: create(:invoice, organization: other_organization, customer: other_customer), provider_session_id: reference)
    end

    it "does not refresh it" do
      expect { result }.not_to have_enqueued_job(PaymentProviders::Ipay::PaymentIntents::RefreshJob)
    end

    it "only re-arms the polling of the webhook's organization" do
      expect { result }.to have_enqueued_job(PaymentProviders::Ipay::PaymentIntents::RearmPollsJob).with(organization).exactly(:once)
    end
  end

  context "when the secret is invalid" do
    let(:secret) { "invalid_secret" }

    it "returns a webhook error" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("webhook_error")
      expect(result.error.error_message).to eq("Invalid webhook secret")
    end

    it "triggers nothing" do
      expect { result }.not_to have_enqueued_job
    end
  end

  context "when the secret is missing" do
    let(:secret) { nil }

    it "returns a webhook error" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("webhook_error")
    end
  end

  context "when the body is not a JSON object with data" do
    let(:body) { "not json" }

    it "returns a webhook error" do
      expect(result).not_to be_success
      expect(result.error.error_message).to eq("Invalid payload")
    end
  end

  context "when the payment provider is not found" do
    subject(:result) { described_class.call(organization_id: organization.id, body:, secret:, code: "unknown") }

    it "returns a failure" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("payment_provider_not_found")
    end
  end
end
