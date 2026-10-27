# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::RearmIpayPollsJob do
  subject(:rearm) { described_class.perform_now }

  let(:organization) { create(:organization) }

  before do
    create(:ipay_provider, organization:)
    create(:flutterwave_provider)
  end

  it "re-arms the polls of each organization with an i-pay provider" do
    rearm

    expect(PaymentProviders::Ipay::PaymentIntents::RearmPollsJob).to have_been_enqueued.with(organization).exactly(:once)
  end
end
