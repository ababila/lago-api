# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::IpayProvider do
  subject(:ipay_provider) { build(:ipay_provider) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:secret_key) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to allow_value("sk_sandbox_abc").for(:secret_key) }
    it { is_expected.to allow_value("sk_live_abc").for(:secret_key) }
    it { is_expected.not_to allow_value("pk_live_abc").for(:secret_key) }
    it { is_expected.to allow_value(nil).for(:success_redirect_url) }
    it { is_expected.to allow_value("https://example.com/success").for(:success_redirect_url) }
    it { is_expected.not_to allow_value("http://example.com/success").for(:success_redirect_url) }
    it { is_expected.not_to allow_value("invalid-url").for(:success_redirect_url) }
    it { is_expected.not_to allow_value("https://example.com/#{"a" * 1025}").for(:success_redirect_url) }

    it "validates uniqueness of the code" do
      expect(ipay_provider).to validate_uniqueness_of(:code).scoped_to(:organization_id)
    end
  end

  describe "#payment_type" do
    it "returns ipay" do
      expect(ipay_provider.payment_type).to eq("ipay")
    end
  end

  describe "#environment" do
    it "returns sandbox for a sandbox key" do
      expect(build(:ipay_provider, secret_key: "sk_sandbox_abc").environment).to eq("sandbox")
    end

    it "returns live for a live key" do
      expect(build(:ipay_provider, secret_key: "sk_live_abc").environment).to eq("live")
    end
  end

  describe "#api_headers" do
    it "authenticates with the key and targets its environment" do
      provider = build(:ipay_provider, secret_key: "sk_live_abc")

      expect(provider.api_headers).to eq(
        "Authorization" => "Bearer sk_live_abc",
        "Ipay-Target-Environment" => "live",
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      )
    end
  end

  describe "#determine_payment_status" do
    it "maps i-pay statuses" do
      expect(ipay_provider.determine_payment_status("succeeded")).to eq(:succeeded)
      expect(ipay_provider.determine_payment_status("pending")).to eq(:processing)
      expect(ipay_provider.determine_payment_status("failed")).to eq(:failed)
      expect(ipay_provider.determine_payment_status("cancelled")).to eq(:failed)
    end
  end

  describe "webhook_secret generation" do
    it "generates a webhook secret on creation" do
      provider = create(:ipay_provider, webhook_secret: nil)

      expect(provider.webhook_secret.length).to eq(64)
    end

    it "keeps an existing webhook secret" do
      provider = create(:ipay_provider, webhook_secret: "existing_secret")

      expect(provider.reload.webhook_secret).to eq("existing_secret")
    end
  end
end
