# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Ipay
      class Create < Base
        REQUIRED_PERMISSION = "organization:integrations:create"

        graphql_name "AddIpayPaymentProvider"
        description "Add i-pay payment provider"

        input_object_class Types::PaymentProviders::IpayInput

        type Types::PaymentProviders::Ipay
      end
    end
  end
end
