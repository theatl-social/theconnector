# frozen_string_literal: true

# Test isolation safety net for the ActiveJob queue adapter.
#
# A few specs set `ActiveJob::Base.queue_adapter = :test` (e.g. to assert with
# `have_enqueued_job`) without restoring it — notably the fork's trusted
# registration specs (spec/services/app_sign_up_service_spec.rb,
# spec/requests/api/v1/accounts_spec.rb). The adapter is global mutable state,
# so under parallel (flatware) execution that leaked `:test` adapter persists to
# later `:inline_jobs` mailer specs running in the same worker. There,
# `deliver_later` enqueues to the test adapter instead of being run inline via
# Sidekiq, so the email is never delivered and matchers report "No emails sent"
# (e.g. disputes/appeals and admin/confirmations system specs).
#
# Whether the leak reaches those specs depends on spec sharding/ordering, which
# varies with the runner's core count — hence it reproduces deterministically on
# our CI runners but not upstream's. Reset the adapter to the application default
# after every example so no spec can leak it into another.
RSpec.configure do |config|
  config.after do
    ActiveJob::Base.queue_adapter = :sidekiq
  end
end
