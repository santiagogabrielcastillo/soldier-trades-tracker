require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Ensures that a master key has been made available in ENV["RAILS_MASTER_KEY"],
  # config/master.key, or an environment key such as config/credentials/production.key.
  config.require_master_key = ENV["SECRET_KEY_BASE_DUMMY"].nil?

  # Serve static files directly from Rails (Kamal proxy does not serve static files).
  config.public_file_server.enabled = true

  # Do not fall back to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through an SSL-terminating reverse proxy
  # (kamal-proxy). Required together with force_ssl so redirect URLs and secure cookies work.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the health check endpoint so Kamal can probe it.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT by default
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Use a real queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Disable caching for Action Mailer templates even if Action Controller caching is enabled.
  config.action_mailer.perform_caching = false

  # Enable locale fallbacks for I18n.
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Active Record encryption keys — set via environment variables.
  # Generate with: bin/rails db:encryption:init
  config.active_record.encryption.primary_key         = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
  config.active_record.encryption.deterministic_key   = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
  config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]

  # DNS rebinding protection — restrict to your domain.
  # Set APP_HOST in your environment (e.g. "trades.example.com").
  config.hosts << ENV["APP_HOST"] if ENV["APP_HOST"]
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
