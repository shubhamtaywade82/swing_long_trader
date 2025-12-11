# frozen_string_literal: true

require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Default cassette options
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [:method, :uri, :body]
  }

  # Filter sensitive data from cassettes
  config.filter_sensitive_data('<DHANHQ_CLIENT_ID>') { ENV['DHANHQ_CLIENT_ID'] }
  config.filter_sensitive_data('<DHANHQ_ACCESS_TOKEN>') { ENV['DHANHQ_ACCESS_TOKEN'] }
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
  config.filter_sensitive_data('<TELEGRAM_BOT_TOKEN>') { ENV['TELEGRAM_BOT_TOKEN'] }
  config.filter_sensitive_data('<TELEGRAM_CHAT_ID>') { ENV['TELEGRAM_CHAT_ID'] }

  # Filter sensitive headers
  config.before_record do |interaction|
    interaction.request.headers.delete('Authorization') if interaction.request.headers['Authorization']
    interaction.request.headers.delete('X-Api-Key') if interaction.request.headers['X-Api-Key']
  end
end

