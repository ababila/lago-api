# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Ipay::PaymentIntents::PollJob do
  subject(:poll) { described_class.perform_now(payment_intent) }

  let(:organization) { create(:organization) }
  let(:ipay_provider) { create(:ipay_provider, organization:) }
  let(:customer) { create(:customer, organization:, payment_provider: "ipay", payment_provider_code: ipay_provider.code) }
  let(:invoice) { create(:invoice, organization:, customer:, currency: "XOF", total_amount_cents: 1500) }
  let(:reference) { SecureRandom.hex(16) }
  let(:created_at) { 2.minutes.ago }
  let(:payment_intent) { create(:payment_intent, invoice:, provider_session_id: reference, created_at:) }
  let(:link_url) { "https://i-pay.money/api/v1/external_payments/#{reference}" }
  let(:link) { {status: "initiated", reference:} }

  before do
    create(:ipay_customer, customer:, payment_provider: ipay_provider)
    stub_request(:get, link_url).to_return(status: 200, body: link.to_json)
  end

  it_behaves_like "a unique job" do
    let(:job_args) { [payment_intent] }
  end

  it "polls again a minute later while the link is new" do
    freeze_time do
      poll

      expect(described_class).to have_been_enqueued.with(payment_intent).at(1.minute.from_now)
    end
  end

  context "when the link is older" do
    let(:created_at) { 25.minutes.ago }

    it "polls every three minutes" do
      freeze_time do
        poll

        expect(described_class).to have_been_enqueued.with(payment_intent).at(3.minutes.from_now)
      end
    end
  end

  context "when the link expired" do
    let(:created_at) { 1.hour.ago }
    let(:link) { {status: "cancelled", has_expire: true, reference:} }

    it "keeps polling, slowly, for a payment still pending" do
      freeze_time do
        poll

        expect(described_class).to have_been_enqueued.with(payment_intent).at(15.minutes.from_now)
      end
    end
  end

  context "when the polling window has ended" do
    let(:created_at) { 3.hours.ago }
    let(:link) { {status: "cancelled", has_expire: true, reference:} }

    it "stops polling" do
      poll

      expect(described_class).not_to have_been_enqueued
    end
  end

  context "when a payment succeeded on the link" do
    let(:link) { {status: "succeeded", reference:, transaction_id: "txn_1", amount: 1500, currency: "XOF"} }

    it "records it and stops polling" do
      poll

      expect(invoice.reload.payment_status).to eq("succeeded")
      expect(described_class).not_to have_been_enqueued
    end
  end

  context "when the link cannot be read" do
    before { stub_request(:get, link_url).to_return(status: 503) }

    it "polls again" do
      poll

      expect(described_class).to have_been_enqueued.with(payment_intent)
    end
  end

  context "when the refresh raises" do
    before do
      allow(PaymentProviders::Ipay::PaymentIntents::RefreshService).to receive(:call).and_raise(ActiveRecord::Deadlocked)
    end

    it "still polls again" do
      expect { poll }.to raise_error(ActiveRecord::Deadlocked)
      expect(described_class).to have_been_enqueued.with(payment_intent)
    end
  end

  context "when the polling window has ended on an unreadable link" do
    let(:created_at) { 3.hours.ago }

    before { stub_request(:get, link_url).to_return(status: 503) }

    it "stops polling and logs an error" do
      allow(Rails.logger).to receive(:error)

      poll

      expect(described_class).not_to have_been_enqueued
      expect(Rails.logger).to have_received(:error).with("[i-pay] polling ended unread payment_intent_id=#{payment_intent.id}")
    end
  end
end
