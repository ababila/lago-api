# frozen_string_literal: true

module Clock
  class RearmIpayPollsJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      organization_ids = PaymentProviders::IpayProvider.distinct.pluck(:organization_id)

      Organization.where(id: organization_ids).find_each do |organization|
        PaymentProviders::Ipay::PaymentIntents::RearmPollsJob.perform_later(organization)
      end
    end
  end
end
