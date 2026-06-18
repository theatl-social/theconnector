# frozen_string_literal: true

require 'rspec/retry'

RSpec.configure do |config|
  config.verbose_retry = true
  config.display_try_failure_messages = true

  # System specs drive the full request stack (and, for :inline_jobs specs,
  # async email delivery) and are occasionally flaky under parallel (flatware)
  # execution — e.g. the browser/email-delivery races in disputes/appeals and
  # admin/confirmations. Retry them so transient failures don't fail CI. A
  # genuinely broken spec fails every attempt and still surfaces.
  config.around :each, type: :system do |example|
    example.run_with_retry retry: 3
  end
end
