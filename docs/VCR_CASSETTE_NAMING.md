# VCR Cassette Naming Conventions

This document describes the naming conventions for VCR cassettes used in the test suite.

## Directory Structure

```
spec/fixtures/vcr_cassettes/
├── dhanhq/
│   ├── instruments/
│   │   ├── list_instruments.yml
│   │   └── get_instrument.yml
│   ├── quotes/
│   │   ├── get_ltp.yml
│   │   └── get_ohlc.yml
│   └── candles/
│       ├── daily_candles.yml
│       ├── weekly_candles.yml
│       └── intraday_candles.yml
├── openai/
│   ├── chat_completions/
│   │   ├── rank_candidates_success.yml
│   │   └── rank_candidates_error.yml
│   └── embeddings/
│       └── create_embedding.yml
└── telegram/
    ├── send_message_success.yml
    └── send_message_error.yml
```

## Naming Convention

### Format
```
{service}/{resource}/{action}_{scenario}.yml
```

### Examples

#### DhanHQ API
- `dhanhq/instruments/list_instruments.yml` - List all instruments
- `dhanhq/quotes/get_ltp_RELIANCE.yml` - Get LTP for specific instrument
- `dhanhq/candles/daily_candles_RELIANCE_2024.yml` - Daily candles for instrument and year
- `dhanhq/candles/intraday_candles_RELIANCE_15m.yml` - Intraday candles with interval

#### OpenAI API
- `openai/chat_completions/rank_candidates_success.yml` - Successful ranking
- `openai/chat_completions/rank_candidates_error.yml` - Error response
- `openai/chat_completions/rank_candidates_rate_limit.yml` - Rate limit error

#### Telegram API
- `telegram/send_message_success.yml` - Successful message send
- `telegram/send_message_error.yml` - Error sending message

## Guidelines

1. **Use descriptive names**: Include the action and scenario (success/error)
2. **Include identifiers**: For specific resources, include identifiers (symbol, ID, etc.)
3. **Group by service**: Organize cassettes by API service
4. **Group by resource**: Further organize by resource type within service
5. **Use lowercase**: All filenames should be lowercase with underscores
6. **Include scenario**: Add `_success`, `_error`, `_rate_limit`, etc. when relevant

## Usage in Tests

```ruby
# In your spec file
describe 'SomeService' do
  it 'fetches data from API', :vcr do
    # VCR will automatically use a cassette named:
    # spec/fixtures/vcr_cassettes/some_service/fetch_data.yml
    result = SomeService.call
    expect(result).to be_successful
  end

  it 'handles API errors', vcr: { cassette_name: 'dhanhq/quotes/get_ltp_error' } do
    # Use specific cassette
    result = SomeService.call
    expect(result).to be_failure
  end
end
```

## Recording New Cassettes

1. Set `VCR_RECORD_MODE=all` in your environment
2. Run the test - VCR will record the interaction
3. Review the cassette to ensure sensitive data is filtered
4. Commit the cassette to version control
5. Set `VCR_RECORD_MODE=once` (default) for future runs

## Sensitive Data Filtering

All cassettes automatically filter:
- `DHANHQ_CLIENT_ID` → `<DHANHQ_CLIENT_ID>`
- `DHANHQ_ACCESS_TOKEN` → `<DHANHQ_ACCESS_TOKEN>`
- `OPENAI_API_KEY` → `<OPENAI_API_KEY>`
- `TELEGRAM_BOT_TOKEN` → `<TELEGRAM_BOT_TOKEN>`
- `TELEGRAM_CHAT_ID` → `<TELEGRAM_CHAT_ID>`
- Authorization headers are removed

## Best Practices

1. **Commit cassettes**: VCR cassettes should be committed to version control
2. **Review before committing**: Ensure no sensitive data leaks through
3. **Update when APIs change**: Re-record cassettes when API responses change
4. **Use descriptive names**: Future developers should understand what each cassette tests
5. **Group related cassettes**: Keep related API interactions together

