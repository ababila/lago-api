# frozen_string_literal: true

module PaymentProviders
  module Ipay
    module PaymentIntents
      class RefreshJob < ApplicationJob
        queue_as do
          if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
            :payments
          else
            :providers
          end
        end

        def perform(payment_intent)
          PaymentProviders::Ipay::PaymentIntents::RefreshService.call!(payment_intent:)
        end
      end
    end
  end
end
