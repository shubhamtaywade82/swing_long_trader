# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'
require 'webmock/minitest'
require 'vcr'

# Configure VCR for API mocking
VCR.configure do |config|
  config.cassette_library_dir = 'test/fixtures/vcr_cassettes'
  config.hook_into :webmock
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [:method, :uri, :body]
  }
  config.filter_sensitive_data('<DHANHQ_CLIENT_ID>') { ENV['DHANHQ_CLIENT_ID'] }
  config.filter_sensitive_data('<DHANHQ_ACCESS_TOKEN>') { ENV['DHANHQ_ACCESS_TOKEN'] }
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
  config.filter_sensitive_data('<TELEGRAM_BOT_TOKEN>') { ENV['TELEGRAM_BOT_TOKEN'] }
end

# Configure WebMock
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    include FactoryBot::Syntax::Methods
  end
end

# Load FactoryBot factories
FactoryBot.find_definitions

