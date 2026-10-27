# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Ipay::PaymentIntents::RefreshJob do
  let(:payment_intent) { create(:payment_intent) }

  before do
    allow(PaymentProviders::Ipay::PaymentIntents::RefreshService).to receive(:call!)
  end

  it "refreshes the payment intent" do
    described_class.perform_now(payment_intent)

    expect(PaymentProviders::Ipay::PaymentIntents::RefreshService).to have_received(:call!).with(payment_intent:)
  end
end
