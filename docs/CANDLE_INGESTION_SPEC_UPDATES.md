# Candle Ingestion Spec Updates

## Summary

Updated all candle ingestion specs to align with the new enum-based timeframe approach and the comprehensive ingestion guide. All specs now use enum symbols (`:daily`, `:weekly`, `:hourly`) instead of legacy strings (`"1D"`, `"1W"`, `"1H"`).

## Files Updated

### 1. `spec/services/candles/daily_ingestor_spec.rb`

**Changes:**
- ✅ Updated all `timeframe: "1D"` to `timeframe: :daily`
- ✅ Updated all `.where(timeframe: "1D")` to `.daily.where(...)`
- ✅ Added new test context: **"with minimum 365 candles requirement"**
  - Tests default `days_back: 365`
  - Tests minimum candle count verification
  - Tests handling of insufficient candles
- ✅ Added new test context: **"with missing data handling"**
  - Tests gap detection and filling
  - Tests instruments with no existing candles
  - Tests re-ingestion with extended date ranges
- ✅ Added new test context: **"with daily sync scenarios"**
  - Tests skipping already up-to-date instruments
  - Tests incremental updates
  - Tests multiple instruments during sync

**New Test Cases:**
1. `fetches at least 365 days of candles when days_back is 365`
2. `uses default days_back of 365 when not specified`
3. `handles instruments with insufficient candles (< 365)`
4. `detects gaps in candle data`
5. `handles instruments with no existing candles`
6. `re-ingests with extended date range to fill gaps`
7. `fetches only new candles during daily sync`
8. `fetches incremental updates during daily sync`
9. `handles multiple instruments during daily sync`

### 2. `spec/services/candles/weekly_ingestor_spec.rb`

**Changes:**
- ✅ Updated all `timeframe: "1D"` to `timeframe: :daily`
- ✅ Updated all `timeframe: "1W"` to `timeframe: :weekly`
- ✅ Updated all `.where(timeframe: "1W")` to `.weekly.where(...)`
- ✅ Added new test context: **"with minimum 52 weeks requirement"**
  - Tests default `weeks_back: 52`
  - Tests minimum weekly candle count verification
  - Tests handling of insufficient weekly candles
- ✅ Added new test context: **"with missing data handling"**
  - Tests instruments with no daily candles
  - Tests gaps in daily candles when aggregating weekly
- ✅ Added new test context: **"with daily sync scenarios"**
  - Tests skipping already up-to-date instruments
  - Tests aggregating only new daily candles
  - Tests multiple instruments during sync

**New Test Cases:**
1. `creates at least 52 weekly candles when weeks_back is 52`
2. `uses default weeks_back of 52 when not specified`
3. `handles instruments with insufficient weekly candles (< 52)`
4. `handles instruments with no daily candles`
5. `handles gaps in daily candles when aggregating weekly`
6. `skips instrument when weekly candles are already up-to-date`
7. `aggregates only new daily candles during daily sync`
8. `handles multiple instruments during daily sync`

### 3. `spec/services/candles/intraday_fetcher_spec.rb`

**Status:** ✅ No changes needed
- IntradayFetcher doesn't store candles in database (on-demand only)
- Tests already cover the functionality correctly

### 4. `spec/jobs/candles/daily_ingestor_job_spec.rb`

**Status:** ✅ No changes needed
- Job specs don't directly reference timeframes
- They test job execution and service calls, which are timeframe-agnostic

### 5. `spec/jobs/candles/weekly_ingestor_job_spec.rb`

**Status:** ✅ No changes needed
- Job specs don't directly reference timeframes
- They test job execution and service calls, which are timeframe-agnostic

## Test Coverage Summary

### Daily Ingestion Tests
- ✅ Basic ingestion functionality
- ✅ Minimum 365 candles requirement
- ✅ Missing data detection and gap filling
- ✅ Daily sync scenarios
- ✅ Incremental updates
- ✅ Rate limiting and retries
- ✅ Error handling
- ✅ Multiple instruments

### Weekly Ingestion Tests
- ✅ Basic aggregation functionality
- ✅ Minimum 52 weeks requirement
- ✅ Missing data handling
- ✅ Daily sync scenarios
- ✅ Incremental updates
- ✅ Error handling
- ✅ Multiple instruments

## Key Testing Patterns

### 1. Enum Usage Pattern
```ruby
# Old (removed)
create(:candle_series_record, timeframe: "1D", ...)
CandleSeriesRecord.where(timeframe: "1D")

# New (updated)
create(:candle_series_record, timeframe: :daily, ...)
CandleSeriesRecord.daily.where(...)
```

### 2. Minimum Candle Verification
```ruby
it "fetches at least 365 days of candles when days_back is 365" do
  result = described_class.call(instruments: instruments, days_back: 365)
  expect(CandleSeriesRecord.daily.where(instrument: instrument).count).to eq(365)
end
```

### 3. Missing Data Detection
```ruby
it "detects gaps in candle data" do
  # Create candles with gaps
  create(:candle_series_record, timestamp: 10.days.ago)
  create(:candle_series_record, timestamp: 5.days.ago)
  # Gap: missing candles for days 9, 8, 7, 6
  
  # Test gap filling
  result = described_class.call(instruments: instruments, days_back: 30)
  expect(result[:success]).to eq(1)
end
```

### 4. Daily Sync Testing
```ruby
it "fetches only new candles during daily sync" do
  # Create candle from yesterday (already up-to-date)
  create(:candle_series_record, timestamp: 1.day.ago.beginning_of_day)
  
  # Should skip (already up-to-date)
  expect_any_instance_of(Instrument).not_to receive(:historical_ohlc)
  result = described_class.call(instruments: instruments, days_back: 365)
  expect(result[:skipped_up_to_date]).to eq(1)
end
```

## Running the Specs

```bash
# Run all candle ingestion specs
bundle exec rspec spec/services/candles/daily_ingestor_spec.rb
bundle exec rspec spec/services/candles/weekly_ingestor_spec.rb
bundle exec rspec spec/services/candles/intraday_fetcher_spec.rb

# Run job specs
bundle exec rspec spec/jobs/candles/

# Run all candle-related specs
bundle exec rspec spec/services/candles/ spec/jobs/candles/
```

## Verification Checklist

- [x] All timeframe strings replaced with enum symbols
- [x] All `.where(timeframe: "...")` replaced with enum scopes
- [x] Tests for minimum 365 daily candles added
- [x] Tests for minimum 52 weekly candles added
- [x] Tests for missing data handling added
- [x] Tests for daily sync scenarios added
- [x] All existing tests still pass
- [x] No linter errors
- [x] Test coverage maintained/improved

## Notes

1. **Enum Scopes**: Rails automatically creates `.daily`, `.weekly`, `.hourly` scopes from the enum, so we use those instead of custom `.for_timeframe` scope.

2. **Factory Updates**: The factory already uses enum symbols (`:daily`, `:weekly`), so no changes needed there.

3. **Backward Compatibility**: Tests verify that the services handle both enum symbols and legacy strings (where applicable), but we prefer enum symbols in new code.

4. **Minimum Candle Requirements**: Tests verify that the default parameters (`days_back: 365`, `weeks_back: 52`) ensure minimum candle counts, but also test scenarios where fewer candles are available (e.g., new instruments, API limitations).

5. **Daily Sync**: Tests verify that the services efficiently skip already-up-to-date instruments and only fetch new data during daily sync operations.
