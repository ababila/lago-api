# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Ipay
      class Update < Base
        REQUIRED_PERMISSION = "organization:integrations:update"

        graphql_name "UpdateIpayPaymentProvider"
        description "Update i-pay payment provider"

        input_object_class Types::PaymentProviders::UpdateInput

        type Types::PaymentProviders::Ipay
      end
    end
  end
end
