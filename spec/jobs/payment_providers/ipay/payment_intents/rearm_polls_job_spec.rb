# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Ipay::PaymentIntents::RearmPollsJob do
  let(:organization) { create(:organization) }

  before do
    allow(PaymentProviders::Ipay::PaymentIntents::RearmPollsService).to receive(:call!)
  end

  it "re-arms the polls of the organization" do
    described_class.perform_now(organization)

    expect(PaymentProviders::Ipay::PaymentIntents::RearmPollsService).to have_received(:call!).with(organization:)
  end

  it_behaves_like "a unique job" do
    let(:job_args) { [organization] }
  end
end
