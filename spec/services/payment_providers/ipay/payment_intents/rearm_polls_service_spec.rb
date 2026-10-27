# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Ipay::PaymentIntents::RearmPollsService do
  subject(:result) { described_class.call(organization:) }

  let(:organization) { create(:organization) }
  let(:ipay_customer) { create(:customer, organization:, payment_provider: "ipay") }
  let(:stripe_customer) { create(:customer, organization:, payment_provider: "stripe") }

  let(:open_intent) do
    create(:payment_intent, invoice: create(:invoice, organization:, customer: ipay_customer), provider_session_id: SecureRandom.hex(16))
  end

  before { open_intent }

  it "polls the i-pay links still in their polling window" do
    expect { result }.to have_enqueued_job(PaymentProviders::Ipay::PaymentIntents::PollJob).with(open_intent).exactly(:once)
  end

  context "when the customer has since moved to another provider" do
    let(:open_intent) do
      create(:payment_intent, invoice: create(:invoice, organization:, customer: stripe_customer), provider_session_id: SecureRandom.hex(16))
    end

    it "still polls the i-pay link" do
      expect { result }.to have_enqueued_job(PaymentProviders::Ipay::PaymentIntents::PollJob).with(open_intent)
    end
  end

  context "with links that are not to be polled" do
    before do
      travel_to(3.hours.ago) do
        create(:payment_intent, invoice: create(:invoice, organization:, customer: ipay_customer), provider_session_id: SecureRandom.hex(16))
      end
      create(:payment_intent, invoice: create(:invoice, organization:, customer: ipay_customer), provider_session_id: nil)
      create(:payment_intent, invoice: create(:invoice, organization:, customer: ipay_customer), provider_session_id: SecureRandom.hex(16), payment_url: nil)
      create(:payment_intent, invoice: create(:invoice, organization:, customer: ipay_customer), provider_session_id: "cs_test_a1b2c3")
      create(:payment_intent, invoice: create(:invoice, organization:, customer: ipay_customer, payment_status: :succeeded), provider_session_id: SecureRandom.hex(16))

      other_organization = create(:organization)
      other_customer = create(:customer, organization: other_organization, payment_provider: "ipay")
      create(:payment_intent, invoice: create(:invoice, organization: other_organization, customer: other_customer), provider_session_id: SecureRandom.hex(16))
    end

    it "polls none of them" do
      expect { result }.to have_enqueued_job(PaymentProviders::Ipay::PaymentIntents::PollJob).exactly(:once)
    end
  end
end
