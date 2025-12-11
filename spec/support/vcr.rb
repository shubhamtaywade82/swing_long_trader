# frozen_string_literal: true

require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Default cassette options
  # Note: We don't match on headers to allow different tokens/IDs
  # The headers will be normalized during recording and matching
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [:method, :uri, :body, :normalized_headers]
  }

  # Filter sensitive data from cassettes (body and query params)
  config.filter_sensitive_data('<DHANHQ_CLIENT_ID>') { ENV['DHANHQ_CLIENT_ID'] || ENV['CLIENT_ID'] }
  config.filter_sensitive_data('<DHANHQ_ACCESS_TOKEN>') { ENV['DHANHQ_ACCESS_TOKEN'] || ENV['ACCESS_TOKEN'] }
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
  config.filter_sensitive_data('<TELEGRAM_BOT_TOKEN>') { ENV['TELEGRAM_BOT_TOKEN'] }
  config.filter_sensitive_data('<TELEGRAM_CHAT_ID>') { ENV['TELEGRAM_CHAT_ID'] }

  # Custom matcher to normalize headers (allows different tokens/IDs to match)
  config.register_request_matcher :normalized_headers do |request1, request2|
    normalize_headers(request1.headers) == normalize_headers(request2.headers)
  end

  # Filter sensitive headers when recording (replace with placeholders)
  config.before_record do |interaction|
    # DhanHQ headers - replace actual values with placeholders
    # Handle case-insensitive header keys
    ['Access-Token', 'access-token', 'ACCESS-TOKEN'].each do |key|
      if interaction.request.headers[key]
        interaction.request.headers[key] = ['<DHANHQ_ACCESS_TOKEN>']
        break
      end
    end

    ['Client-Id', 'client-id', 'CLIENT-ID'].each do |key|
      if interaction.request.headers[key]
        interaction.request.headers[key] = ['<DHANHQ_CLIENT_ID>']
        break
      end
    end

    # OpenAI headers
    ['Authorization', 'authorization', 'AUTHORIZATION'].each do |key|
      if interaction.request.headers[key]
        auth_header = interaction.request.headers[key].first
        if auth_header&.start_with?('Bearer ')
          interaction.request.headers[key] = ['Bearer <OPENAI_API_KEY>']
        else
          interaction.request.headers.delete(key)
        end
        break
      end
    end

    # Telegram headers (if used)
    ['X-Telegram-Bot-Token', 'x-telegram-bot-token'].each do |key|
      if interaction.request.headers[key]
        interaction.request.headers[key] = ['<TELEGRAM_BOT_TOKEN>']
        break
      end
    end

    # Other sensitive headers
    ['X-Api-Key', 'x-api-key'].each do |key|
      interaction.request.headers.delete(key) if interaction.request.headers[key]
    end
  end
end

# Helper method to normalize headers for matching
# This allows requests with different tokens/IDs to match the same cassette
# Headers are case-insensitive in HTTP, so we normalize the keys
def normalize_headers(headers)
  return {} unless headers

  normalized = {}
  headers.each do |key, value|
    # Normalize header keys to lowercase for comparison
    normalized_key = key.to_s.downcase
    normalized[normalized_key] = value
  end

  # Normalize sensitive headers to placeholders for matching
  if normalized['access-token']
    normalized['access-token'] = ['<DHANHQ_ACCESS_TOKEN>']
  end
  if normalized['client-id']
    normalized['client-id'] = ['<DHANHQ_CLIENT_ID>']
  end
  if normalized['authorization']
    auth = normalized['authorization'].first
    if auth&.start_with?('Bearer ')
      normalized['authorization'] = ['Bearer <OPENAI_API_KEY>']
    end
  end
  if normalized['x-telegram-bot-token']
    normalized['x-telegram-bot-token'] = ['<TELEGRAM_BOT_TOKEN>']
  end

  normalized
end

