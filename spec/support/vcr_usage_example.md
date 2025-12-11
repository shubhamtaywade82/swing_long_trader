# VCR Usage Guide

## Overview

VCR (Video Cassette Recorder) is configured to record HTTP interactions and sanitize sensitive data like API tokens and client IDs.

## Configuration

The VCR configuration is in `spec/support/vcr.rb`. It:

1. **Records HTTP interactions** to `spec/fixtures/vcr_cassettes/`
2. **Filters sensitive data** from request/response bodies
3. **Replaces sensitive headers** with placeholders:
   - `Access-Token` → `<DHANHQ_ACCESS_TOKEN>`
   - `Client-Id` → `<DHANHQ_CLIENT_ID>`
   - `Authorization: Bearer <token>` → `Bearer <OPENAI_API_KEY>`
4. **Normalizes headers for matching** so different tokens/IDs can use the same cassette

## Usage in Tests

### Basic Usage

Add `:vcr` metadata to your test:

```ruby
RSpec.describe 'MyService', :vcr do
  it 'makes an API call' do
    result = MyService.call
    expect(result).to be_successful
  end
end
```

### Per-Example Usage

```ruby
it 'makes an API call', :vcr do
  result = MyService.call
  expect(result).to be_successful
end
```

### Custom Cassette Names

```ruby
it 'makes an API call', vcr: { cassette_name: 'my_service/call' } do
  result = MyService.call
  expect(result).to be_successful
end
```

## How It Works

1. **First run** (no cassette exists):
   - VCR records the actual HTTP request/response
   - Sensitive headers are replaced with placeholders
   - Cassette is saved to `spec/fixtures/vcr_cassettes/`

2. **Subsequent runs** (cassette exists):
   - VCR replays the recorded response
   - No actual HTTP request is made
   - Headers are normalized for matching (different tokens/IDs work)

## Sensitive Data Filtering

The following ENV variables are automatically filtered:

- `DHANHQ_CLIENT_ID` / `CLIENT_ID` → `<DHANHQ_CLIENT_ID>`
- `DHANHQ_ACCESS_TOKEN` / `ACCESS_TOKEN` → `<DHANHQ_ACCESS_TOKEN>`
- `OPENAI_API_KEY` → `<OPENAI_API_KEY>`
- `TELEGRAM_BOT_TOKEN` → `<TELEGRAM_BOT_TOKEN>`
- `TELEGRAM_CHAT_ID` → `<TELEGRAM_CHAT_ID>`

## Header Normalization

Headers are normalized so that:
- Different access tokens match the same cassette
- Different client IDs match the same cassette
- Different API keys match the same cassette

This allows cassettes to be shared across different environments without exposing sensitive data.

## Regenerating Cassettes

To regenerate a cassette (e.g., after API changes):

1. Delete the cassette file from `spec/fixtures/vcr_cassettes/`
2. Run the test again - it will record a new cassette

Or use `record: :new_episodes` in cassette options:

```ruby
it 'makes an API call', vcr: { record: :new_episodes } do
  result = MyService.call
end
```

## Best Practices

1. **Commit cassettes to git** - They contain sanitized data and help tests run offline
2. **Use descriptive cassette names** - Organize by service/feature
3. **Don't commit real tokens** - The configuration ensures placeholders are used
4. **Regenerate cassettes** when API contracts change
5. **Use `:vcr` metadata** on integration tests that make real HTTP calls

