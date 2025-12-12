# frozen_string_literal: true

# This file is copied to spec/ when you run 'rails generate rspec:install'
require "spec_helper"
ENV["RAILS_ENV"] ||= "test"

# Suppress warnings from third-party gems while loading Rails
# These warnings come from:
# - mail gem: parser warnings (statement not reached)
# - technical-analysis gem: unused variable warnings
# - DhanHQ gem: method redefinition and circular require warnings
# - ActiveRecord: enum scope redefinition (fixed in code, but may still appear)
# - Rails core and third-party rake tasks: method redefinition when tasks are loaded multiple times
original_verbose = $VERBOSE
begin
  $VERBOSE = nil
  require_relative "../config/environment"
ensure
  $VERBOSE = original_verbose
end

# Suppress method redefinition warnings from Rails core and third-party rake tasks
# These occur when rake tasks are loaded multiple times during test runs
# This is harmless and expected behavior in Rails applications
# We use a custom warning handler to filter out these specific warnings
module WarningFilter
  def self.setup
    return unless defined?(Warning) && Warning.respond_to?(:warn)

    # Store original warn method
    original_warn = Warning.method(:warn)

    # Override Warning.warn to filter rake task warnings
    Warning.define_singleton_method(:warn) do |message, category: nil|
      # Filter out method redefinition warnings from rake tasks
      return if message.is_a?(String) && (
        message.match?(/method redefined.*discarding old/) ||
        message.include?("previous definition of") ||
        message.include?("already initialized constant") ||
        message.include?("cache_digests.rake") ||
        message.match?(/jsbundling.*build\.rake/) ||
        message.include?("turbo_tasks.rake") ||
        message.include?("stimulus_tasks.rake") ||
        message.match?(/cssbundling.*build\.rake/) ||
        message.match?(/railties.*tasks.*log\.rake/) ||
        message.match?(/railties.*tasks.*misc\.rake/)
      )

      # Call original warning handler
      original_warn.call(message, category: category)
    end
  end
end

WarningFilter.setup
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
# Add additional requires below this line. Rails is not loaded until this point!

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for purpose of convenience. However, it
# can cause issues if you have version control enabled and you re-run
# `rails generate rspec:install` multiple times. It is recommended that you
# comment it out until you actually need it. For more information, see:
# https://rspec.info/features/3-12/rspec-core/configuration/zero-monkey-patching-mode/
Rails.root.glob("spec/support/**/*.rb").each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [
    Rails.root.join("spec/fixtures"),
  ]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = false

  # Configure ActiveJob test adapter
  config.before do
    ActiveJob::Base.queue_adapter = :test
  end

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  #
  # You can disable this behaviour by removing the line below, and instead
  # explicitly tag your specs with their type, e.g.:
  #
  #     RSpec.describe UsersController, type: :controller do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://rspec.info/features/6-0/rspec-rails
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")

  # Include FactoryBot syntax methods
  config.include FactoryBot::Syntax::Methods
end
