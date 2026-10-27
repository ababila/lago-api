# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::IpayService do
  subject(:ipay_service) { described_class.new }

  include_context "with mocked security logger"

  let_it_be(:organization) { create(:organization) }

  describe "#create_or_update" do
    let(:args) do
      {
        organization: organization,
        code: "ipay_1",
        name: "Ipay Provider",
        secret_key: "sk_sandbox_test_secret_key",
        success_redirect_url: "https://example.com/success"
      }
    end

    context "when creating a new provider" do
      it "creates a new ipay provider" do
        result = ipay_service.create_or_update(**args)

        expect(result).to be_success
        expect(result.ipay_provider).to be_a(PaymentProviders::IpayProvider)
        expect(result.ipay_provider.organization_id).to eq(organization.id)
        expect(result.ipay_provider.code).to eq("ipay_1")
        expect(result.ipay_provider.name).to eq("Ipay Provider")
        expect(result.ipay_provider.secret_key).to eq("sk_sandbox_test_secret_key")
        expect(result.ipay_provider.success_redirect_url).to eq("https://example.com/success")
      end

      it_behaves_like "produces a security log", "integration.created" do
        before { ipay_service.create_or_update(**args) }
      end
    end

    context "when updating an existing provider" do
      let(:existing_provider) do
        create(
          :ipay_provider,
          organization: organization,
          code: "ipay_1",
          name: "Old Name",
          secret_key: "sk_sandbox_old_secret_key",
          success_redirect_url: "https://old.example.com/return"
        )
      end

      before { existing_provider }

      it "updates the existing provider" do
        result = ipay_service.create_or_update(**args)

        expect(result).to be_success
        expect(result.ipay_provider.id).to eq(existing_provider.id)
        expect(result.ipay_provider.name).to eq("Ipay Provider")
        expect(result.ipay_provider.secret_key).to eq("sk_sandbox_test_secret_key")
        expect(result.ipay_provider.success_redirect_url).to eq("https://example.com/success")
      end

      it_behaves_like "produces a security log", "integration.updated" do
        before { ipay_service.create_or_update(**args) }
      end

      context "when code is updated" do
        let(:customer) { create(:customer, organization: organization, payment_provider_code: "ipay_1") }
        let!(:ipay_customer) do
          create(:ipay_customer, customer: customer, payment_provider: existing_provider)
        end

        let(:args) do
          {
            organization: organization,
            id: existing_provider.id,
            code: "ipay_2",
            name: "Updated Ipay Provider",
            secret_key: "sk_sandbox_updated_secret_key",
            success_redirect_url: "https://updated.example.com/return"
          }
        end

        it "updates the provider and associated customer codes" do
          result = ipay_service.create_or_update(**args)

          expect(result).to be_success
          expect(result.ipay_provider.code).to eq("ipay_2")
          ipay_customer.reload
          expect(ipay_customer.customer.payment_provider_code).to eq("ipay_2")
        end
      end
    end

    context "when partial update with only specific fields" do
      let(:existing_provider) do
        create(
          :ipay_provider,
          organization: organization,
          code: "ipay_1",
          name: "Original Name",
          secret_key: "sk_sandbox_original_secret_key",
          success_redirect_url: "https://original.example.com/return"
        )
      end

      before { existing_provider }

      it "updates only the provided fields" do
        partial_args = {
          organization: organization,
          id: existing_provider.id,
          name: "Updated Name Only"
        }

        result = ipay_service.create_or_update(**partial_args)

        expect(result).to be_success
        expect(result.ipay_provider.name).to eq("Updated Name Only")
        expect(result.ipay_provider.secret_key).to eq("sk_sandbox_original_secret_key") # unchanged
        expect(result.ipay_provider.success_redirect_url).to eq("https://original.example.com/return") # unchanged
      end

      it "keeps the secret key when the masked value is sent back" do
        result = ipay_service.create_or_update(
          organization:,
          id: existing_provider.id,
          secret_key: "••••••••…key"
        )

        expect(result).to be_success
        expect(result.ipay_provider.reload.secret_key).to eq("sk_sandbox_original_secret_key")
      end
    end

    context "when validation fails" do
      let(:args) do
        {
          organization: organization,
          code: "ipay_test",
          name: "", # Invalid empty name
          secret_key: "sk_sandbox_test_secret_key"
        }
      end

      it "returns a failure result with validation errors" do
        result = ipay_service.create_or_update(**args)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end
    end

    context "when finding existing provider by code" do
      let(:existing_provider) do
        create(
          :ipay_provider,
          organization: organization,
          code: "ipay_1"
        )
      end

      before { existing_provider }

      it "finds and updates the existing provider by code" do
        update_args = args.merge(code: "ipay_1", name: "Updated via Code")

        result = ipay_service.create_or_update(**update_args)

        expect(result).to be_success
        expect(result.ipay_provider.id).to eq(existing_provider.id)
        expect(result.ipay_provider.name).to eq("Updated via Code")
      end
    end
  end
end
