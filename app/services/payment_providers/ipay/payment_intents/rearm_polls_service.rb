# frozen_string_literal: true

module PaymentProviders
  module Ipay
    module PaymentIntents
      # Restarts the polling of the organization's i-pay links still in their polling window. A poll
      # scheduled in Redis can be lost, so the database is the list of links to watch.
      class RearmPollsService < BaseService
        Result = BaseResult

        def initialize(organization:)
          @organization = organization

          super
        end

        def call
          open_payment_intents.find_each do |payment_intent|
            PaymentProviders::Ipay::PaymentIntents::PollJob.perform_later(payment_intent)
          end

          result
        end

        private

        attr_reader :organization

        # A link is told apart by its reference, 32 hex characters, as its customer may have changed
        # provider since. A link of a paid invoice is left to its own poll.
        def open_payment_intents
          PaymentIntent
            .where(organization:)
            .where(created_at: ::PaymentProviders::IpayProvider::POLLING_WINDOW.ago..)
            .where.not(payment_url: nil)
            .where("payment_intents.provider_session_id ~ '^[0-9a-f]{32}$'")
            .joins(:invoice)
            .merge(Invoice.where.not(payment_status: :succeeded))
        end
      end
    end
  end
end
