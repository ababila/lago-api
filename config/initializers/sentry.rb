# frozen_string_literal: true

if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.release = LagoUtils::Version.call(default: Rails.env).sha_or_number
    config.breadcrumbs_logger = %i[active_support_logger http_logger]
    config.traces_sample_rate = 0
    config.traces_sample_rate = ENV["SENTRY_TRACES_SAMPLE_RATE"].to_f
    config.environment = ENV["SENTRY_ENVIRONMENT"] || Rails.env
    # An i-pay link URL holds a reference that reads the payer's details without a key.
    config.before_breadcrumb = lambda do |breadcrumb, _hint|
      url = breadcrumb.data.is_a?(Hash) && breadcrumb.data[:url]
      breadcrumb.data[:url] = url.sub(%r{/external_payments/[^/?#]+}, "/external_payments/[FILTERED]") if url.is_a?(String)
      breadcrumb
    end
  end
end
