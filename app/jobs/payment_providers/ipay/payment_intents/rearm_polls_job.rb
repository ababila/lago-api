# frozen_string_literal: true

module PaymentProviders
  module Ipay
    module PaymentIntents
      class RearmPollsJob < ApplicationJob
        queue_as do
          if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
            :payments
          else
            :providers
          end
        end

        unique :until_executed, on_conflict: :log

        def perform(organization)
          PaymentProviders::Ipay::PaymentIntents::RearmPollsService.call!(organization:)
        end
      end
    end
  end
end
