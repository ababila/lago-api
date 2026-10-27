# frozen_string_literal: true

module PaymentProviders
  module Ipay
    module PaymentIntents
      # Polls a link until a payment succeeds on it or its polling window ends, each run scheduling
      # the next one. i-pay does not retry a webhook it failed to deliver, so polling is the authority.
      class PollJob < ApplicationJob
        queue_as do
          if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
            :payments
          else
            :providers
          end
        end

        # The poll already scheduled for a link absorbs the ones a re-arm enqueues.
        unique :until_executing, on_conflict: :log

        def perform(payment_intent)
          result = PaymentProviders::Ipay::PaymentIntents::RefreshService.call(payment_intent:)
        ensure
          # Also after an error: without a clock, nothing else restarts the polling of this link.
          poll_again_or_stop(payment_intent, result) unless result&.success? && result.payment
        end

        private

        def poll_again_or_stop(payment_intent, result)
          age = Time.current - payment_intent.created_at

          if age < ::PaymentProviders::IpayProvider::POLLING_WINDOW
            self.class.set(wait: next_poll_delay(age)).perform_later(payment_intent)
          elsif result&.success?
            Rails.logger.info("[i-pay] polling ended unpaid payment_intent_id=#{payment_intent.id} status=#{result.link_status}")
          else
            Rails.logger.error("[i-pay] polling ended unread payment_intent_id=#{payment_intent.id}")
          end
        end

        def next_poll_delay(age)
          if age < 10.minutes
            1.minute
          elsif age < ::PaymentProviders::IpayProvider::LINK_TTL + ::PaymentProviders::IpayProvider::PAYMENT_INTENT_TTL
            3.minutes
          else
            15.minutes
          end
        end
      end
    end
  end
end
