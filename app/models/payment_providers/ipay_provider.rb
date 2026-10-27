# frozen_string_literal: true

module PaymentProviders
  class IpayProvider < BaseProvider
    API_URL = "https://i-pay.money/api/v1"
    CURRENCY = "XOF"
    MINIMUM_AMOUNT = 50

    # i-pay expires every hosted link 30 minutes after it is created. The payment intent expires
    # earlier, so Lago never hands out a link that dies while the payer confirms on their phone.
    LINK_TTL = 30.minutes
    PAYMENT_INTENT_TTL = 20.minutes

    # Links are polled until a payment succeeds or this long after creation. It covers a mobile
    # money payment still pending when the link expires.
    POLLING_WINDOW = LINK_TTL + 2.hours

    # Covers DNS failures, refused or reset connections and timeouts.
    NETWORK_ERRORS = [SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Timeout::Error].freeze

    SUCCESS_STATUSES = %w[succeeded].freeze
    PROCESSING_STATUSES = %w[initiated pending].freeze
    FAILED_STATUSES = %w[failed cancelled].freeze

    validates :secret_key, presence: true, format: {with: /\Ask_(sandbox|live)_/}
    validates :success_redirect_url, url: true, allow_nil: true, length: {maximum: 1024}
    validate :success_redirect_url_is_https

    secrets_accessors :secret_key, :webhook_secret

    before_create :generate_webhook_secret

    def payment_type
      "ipay"
    end

    def api_url
      API_URL
    end

    # Sandbox and live are separate i-pay accounts, each with its own key.
    def environment
      secret_key.to_s.start_with?("sk_live_") ? "live" : "sandbox"
    end

    def api_headers
      {
        "Authorization" => "Bearer #{secret_key}",
        "Ipay-Target-Environment" => environment,
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }
    end

    private

    def generate_webhook_secret
      self.webhook_secret = SecureRandom.hex(32) if webhook_secret.blank?
    end

    # i-pay refuses a redirection URL that is not HTTPS.
    def success_redirect_url_is_https
      return if success_redirect_url.blank?
      return if success_redirect_url.start_with?("https://")

      errors.add(:success_redirect_url, :url_invalid)
    end
  end
end
