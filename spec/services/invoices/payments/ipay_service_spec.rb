# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::IpayService do
  let(:organization) { create(:organization) }
  let(:ipay_provider) { create(:ipay_provider, organization:, secret_key: "sk_sandbox_key") }
  let(:customer) { create(:customer, organization:, payment_provider: "ipay", payment_provider_code: ipay_provider.code) }
  let(:ipay_customer) { create(:ipay_customer, customer:, payment_provider: ipay_provider) }
  let(:invoice) do
    create(:invoice, organization:, customer:, currency: "XOF", total_amount_cents: 1500, number: "INV-001")
  end

  before { ipay_customer }

  describe ".call(:generate_payment_url)" do
    subject(:result) { described_class.call(:generate_payment_url, invoice, payment_intent) }

    let(:payment_intent) { create(:payment_intent, invoice:, payment_url: nil) }
    let(:links_url) { "https://i-pay.money/api/v1/external_payments" }
    let(:page_url) { "https://i-pay.money/external_payments/5cd8447270f6/preview" }

    before do
      stub_request(:post, links_url)
        .to_return(status: 200, body: {status: "initiated", should_expire: true, page_url:}.to_json)
    end

    it "creates a link for the amount due, under a random reference" do
      freeze_time do
        expect(result).to be_success
        expect(result.payment_url).to eq(page_url)
        expect(result.provider_session_id).to match(/\A\h{32}\z/)
        expect(payment_intent.reload).to have_attributes(
          provider_session_id: result.provider_session_id,
          expires_at: 20.minutes.from_now
        )

        expect(WebMock).to have_requested(:post, links_url).with(
          headers: {
            "Authorization" => "Bearer sk_sandbox_key",
            "Ipay-Target-Environment" => "sandbox",
            "Ipay-Payment-Type" => "external_payment"
          },
          body: {
            title: "#{invoice.billing_entity.name} - Invoice INV-001",
            amount: 1500,
            reference: result.provider_session_id,
            on_success_redirection_url: "https://example.com/billing/return",
            on_failed_redirection_url: "https://example.com/billing/return"
          }
        )
      end
    end

    it "starts the polling of the link" do
      expect { result }.to have_enqueued_job_after_commit(PaymentProviders::Ipay::PaymentIntents::PollJob).with(payment_intent)
    end

    it "re-arms the polling of the organization's other links" do
      expect { result }.to have_enqueued_job_after_commit(PaymentProviders::Ipay::PaymentIntents::RearmPollsJob).with(organization)
    end

    it "uses a new reference for each link" do
      first_reference = described_class.call(:generate_payment_url, invoice, payment_intent).provider_session_id

      expect(result.provider_session_id).not_to eq(first_reference)
    end

    context "without a success redirect URL" do
      let(:ipay_provider) { create(:ipay_provider, organization:, success_redirect_url: nil) }

      it "lets i-pay show its own result page" do
        result

        expect(WebMock).to(have_requested(:post, links_url).with { |request|
          !JSON.parse(request.body).key?("on_success_redirection_url") &&
            !JSON.parse(request.body).key?("on_failed_redirection_url")
        })
      end
    end

    context "when the invoice is not in XOF" do
      let(:invoice) { create(:invoice, organization:, customer:, currency: "EUR", total_amount_cents: 1500) }

      it "refuses the invoice without calling i-pay" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(currency: ["value_is_invalid"])
        expect(WebMock).not_to have_requested(:post, links_url)
      end
    end

    context "when the amount due is under the i-pay minimum" do
      let(:invoice) { create(:invoice, organization:, customer:, currency: "XOF", total_amount_cents: 49) }

      it "refuses the invoice without calling i-pay" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(total_due_amount_cents: ["invalid_amount"])
        expect(WebMock).not_to have_requested(:post, links_url)
      end
    end

    context "when i-pay refuses the link" do
      before do
        stub_request(:post, links_url).to_return(status: 422, body: {errors: ["Amount is invalid"]}.to_json)
      end

      it "returns a third party failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
        expect(result.error.third_party).to eq("i-pay")
        expect(result.error.error_message).to eq({errors: ["Amount is invalid"]}.to_json)
      end
    end

    context "when i-pay does not answer" do
      before { stub_request(:post, links_url).to_timeout }

      it "returns a third party failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
      end
    end
  end

  describe ".call(:expire_payment_url)" do
    let(:payment_intent) { create(:payment_intent, invoice:, provider_session_id: SecureRandom.hex(16)) }

    it "does nothing, as i-pay links cannot be cancelled" do
      result = described_class.call(:expire_payment_url, invoice, payment_intent)

      expect(result).to be_success
      expect(WebMock).not_to have_requested(:any, /i-pay.money/)
    end
  end

  describe ".call(:update_payment_status)" do
    subject(:result) do
      described_class.call(:update_payment_status, invoice:, provider_payment_id: "txn_1", amount_cents:, currency:)
    end

    let(:amount_cents) { 1500 }
    let(:currency) { "XOF" }

    it "records the payment and settles the invoice" do
      expect(result).to be_success
      expect(result.payment).to have_attributes(
        payable: invoice,
        customer:,
        payment_provider_id: ipay_provider.id,
        payment_provider_customer_id: ipay_customer.id,
        provider_payment_id: "txn_1",
        amount_cents: 1500,
        amount_currency: "XOF",
        status: "succeeded",
        payable_payment_status: "succeeded",
        error_code: nil
      )
      expect(invoice.reload).to have_attributes(
        payment_status: "succeeded",
        total_paid_amount_cents: 1500,
        ready_for_payment_processing: false,
        payment_attempts: 1
      )
    end

    it "sends the payment.succeeded webhook" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("payment.succeeded", Payment)
    end

    context "when the payment is already recorded" do
      before { described_class.call(:update_payment_status, invoice:, provider_payment_id: "txn_1", amount_cents:, currency:) }

      it "returns it without recording it twice" do
        expect { result }.not_to change(Payment, :count)
        expect(result.payment.provider_payment_id).to eq("txn_1")
        expect(invoice.reload.payment_attempts).to eq(1)
      end
    end

    context "when the invoice was voided" do
      let(:invoice) do
        create(:invoice, :voided, organization:, customer:, currency: "XOF", total_amount_cents: 1500)
      end

      it "still settles it with the payment" do
        expect(result.payment.payable_payment_status).to eq("succeeded")
        expect(invoice.reload.payment_status).to eq("succeeded")
      end
    end

    shared_examples "a held payment" do |reason|
      it "records the payment without settling the invoice" do
        expect(result).to be_success
        expect(result.payment).to have_attributes(
          provider_payment_id: "txn_1",
          status: "succeeded",
          payable_payment_status: nil,
          error_code: reason
        )
        expect(invoice.reload.total_paid_amount_cents).to eq(paid_before)
      end

      it "sends no payment.succeeded webhook" do
        expect { result }.not_to have_enqueued_job(SendWebhookJob).with("payment.succeeded", Payment)
      end
    end

    context "when the amount differs from the amount due" do
      let(:amount_cents) { 1000 }
      let(:paid_before) { 0 }

      it_behaves_like "a held payment", "ipay_amount_mismatch"
    end

    context "when the amount is unknown" do
      let(:amount_cents) { nil }
      let(:paid_before) { 0 }

      it_behaves_like "a held payment", "ipay_amount_mismatch"
    end

    context "when the currency is not the invoice currency" do
      let(:currency) { "EUR" }
      let(:paid_before) { 0 }

      it_behaves_like "a held payment", "ipay_currency_mismatch"
    end

    context "when the invoice was already paid by another payment" do
      let(:paid_before) { 1500 }

      before do
        described_class.call(:update_payment_status, invoice:, provider_payment_id: "txn_0", amount_cents: 1500, currency:)
      end

      it_behaves_like "a held payment", "ipay_invoice_already_paid"
    end
  end
end
