# Candle Ingestion Guide: From Instruments to Trading Data

Complete guide for importing instruments and ingesting candles for daily, weekly, and hourly timeframes with minimum 365 candles per timeframe, handling missing data, and setting up daily sync.

## Table of Contents

1. [Overview](#overview)
2. [Step 1: Import Instruments](#step-1-import-instruments)
3. [Step 2: Initial Candle Ingestion](#step-2-initial-candle-ingestion)
4. [Step 3: Daily Sync Process](#step-3-daily-sync-process)
5. [Handling Missing Data](#handling-missing-data)
6. [Verification & Monitoring](#verification--monitoring)
7. [Troubleshooting](#troubleshooting)

---

## Overview

This guide covers the complete data pipeline:

1. **Import Instruments** - Load instrument master data from DhanHQ
2. **Initial Ingestion** - Fetch historical candles (minimum 365 days/candles per timeframe)
3. **Daily Sync** - Update candles daily to keep data fresh
4. **Handle Missing Data** - Detect and fill gaps in candle data

### Timeframes Supported

- **Daily (`:daily`)** - End-of-day candles, minimum 365 days
- **Weekly (`:weekly`)** - Weekly aggregated candles, minimum 52 weeks (~365 days)
- **Hourly (`:hourly`)** - Hourly candles, minimum 365 hours (~15 days of trading hours)

---

## Step 1: Import Instruments

Before ingesting candles, you need instruments in the database.

### 1.1 Import from DhanHQ CSV

```ruby
# Via Rails console
rails runner "InstrumentsImporter.import_from_url"

# Or via rake task
rake instruments:import
```

### 1.2 Verify Instruments

```ruby
# Check instrument count
Instrument.count
# => 5000+ (example)

# Check by segment
Instrument.where(segment: 'equity').count
Instrument.where(segment: 'index').count

# Check instruments have security_id (required for API calls)
Instrument.where.not(security_id: nil).count
```

### 1.3 Filter Instruments for Candle Ingestion

Only equity and index instruments are ingested:

```ruby
# Instruments that will be used for candle ingestion
instruments = Instrument.where(segment: %w[equity index])
instruments.count
```

---

## Step 2: Initial Candle Ingestion

### 2.1 Daily Candles (Minimum 365 Days)

Daily candles are fetched from DhanHQ API and stored directly.

```ruby
# Via Rails console - ingest for all instruments
rails runner "Candles::DailyIngestor.call"

# With custom parameters
rails runner "Candles::DailyIngestor.call(days_back: 365)"

# For specific instruments
instruments = Instrument.where(segment: 'equity').limit(10)
rails runner "Candles::DailyIngestor.call(instruments: #{instruments.map(&:id)})"

# Via background job
Candles::DailyIngestorJob.perform_later
```

**What it does:**
- Fetches historical daily candles from DhanHQ API
- Default: 365 days back from yesterday
- Skips instruments already up-to-date
- Handles rate limiting with exponential backoff
- Progress logging every 10 instruments

**Expected Output:**
```
📊 Starting daily candle ingestion for 5000 instruments...
   Rate limiting: 0.5s delay every 5 requests
   Max retries: 3 with exponential backoff

   Progress: 10/5000 (0.2%) | Success: 10 | Failed: 0 | Up-to-date: 0 | ETA: 45.2 min
   Progress: 20/5000 (0.4%) | Success: 20 | Failed: 0 | Up-to-date: 0 | ETA: 44.8 min
   ...

✅ Daily candle ingestion completed!
   Duration: 42.3 minutes
   Processed: 5000
   Success: 4985
   Failed: 15
   Total candles: 1,825,000
```

**Verify Daily Candles:**
```ruby
# Check total daily candles
CandleSeriesRecord.daily.count

# Check candles per instrument
CandleSeriesRecord.daily.group(:instrument_id).count

# Check date range
CandleSeriesRecord.daily.minimum(:timestamp)
CandleSeriesRecord.daily.maximum(:timestamp)

# Check specific instrument
instrument = Instrument.find_by(symbol_name: 'RELIANCE')
CandleSeriesRecord.daily.where(instrument: instrument).count
latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: :daily)
puts "Latest daily candle: #{latest.timestamp.to_date}"
```

### 2.2 Weekly Candles (Minimum 52 Weeks)

Weekly candles are aggregated from daily candles (no API calls needed).

```ruby
# Via Rails console - ingest for all instruments
rails runner "Candles::WeeklyIngestor.call"

# With custom parameters (52 weeks = ~365 days)
rails runner "Candles::WeeklyIngestor.call(weeks_back: 52)"

# For specific instruments
instruments = Instrument.where(segment: 'equity').limit(10)
rails runner "Candles::WeeklyIngestor.call(instruments: #{instruments.map(&:id)})"

# Via background job
Candles::WeeklyIngestorJob.perform_later
```

**What it does:**
- Loads daily candles from database
- Aggregates daily candles into weekly candles (Monday to Sunday)
- Default: 52 weeks back (~365 days)
- Skips instruments already up-to-date
- No API calls (uses existing daily candles)

**Expected Output:**
```
📊 Starting weekly candle ingestion for 5000 instruments...
   Aggregating from daily candles (no API calls needed)

   Progress: 10/5000 (0.2%) | Success: 10 | Failed: 0 | Up-to-date: 0 | ETA: 2.1 min
   ...

✅ Weekly candle ingestion completed!
   Duration: 1.8 minutes
   Processed: 5000
   Success: 4985
   Failed: 15
   Total candles: 260,000
```

**Verify Weekly Candles:**
```ruby
# Check total weekly candles
CandleSeriesRecord.weekly.count

# Check candles per instrument (should be ~52)
CandleSeriesRecord.weekly.group(:instrument_id).count

# Check specific instrument
instrument = Instrument.find_by(symbol_name: 'RELIANCE')
CandleSeriesRecord.weekly.where(instrument: instrument).count
latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: :weekly)
puts "Latest weekly candle: #{latest.timestamp.to_date}"
```

### 2.3 Hourly Candles (Minimum 365 Hours)

Hourly candles are fetched from DhanHQ API. Note: 365 hours = ~15 trading days (market hours only).

```ruby
# Via Rails console - fetch hourly candles
# Note: Hourly candles are typically fetched on-demand, not bulk ingested
# For initial bulk ingestion, you can use IntradayFetcher

# Fetch for specific instrument
instrument = Instrument.find_by(symbol_name: 'RELIANCE')
result = Candles::IntradayFetcher.call(
  instrument: instrument,
  interval: '60',  # 60 minutes = 1 hour
  days: 15  # Fetch last 15 days to get ~365 hours
)

# Bulk fetch for multiple instruments
instruments = Instrument.where(segment: 'equity').limit(10)
instruments.each do |instrument|
  result = Candles::IntradayFetcher.call(
    instrument: instrument,
    interval: '60',
    days: 15
  )
  puts "#{instrument.symbol_name}: #{result[:success] ? 'Success' : 'Failed'}"
end
```

**What it does:**
- Fetches intraday candles from DhanHQ API
- Aggregates to hourly candles
- Stores with `:hourly` timeframe enum
- Handles rate limiting

**Verify Hourly Candles:**
```ruby
# Check total hourly candles
CandleSeriesRecord.hourly.count

# Check specific instrument
instrument = Instrument.find_by(symbol_name: 'RELIANCE')
CandleSeriesRecord.hourly.where(instrument: instrument).count
latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: :hourly)
puts "Latest hourly candle: #{latest.timestamp}"
```

---

## Step 3: Daily Sync Process

After initial ingestion, set up daily sync to keep candles up-to-date.

### 3.1 Daily Candle Sync

Daily candles should be synced every day after market close (typically 3:30 PM IST).

**Option 1: Scheduled Job (Recommended)**

Add to `config/schedule.rb` (if using whenever gem) or your job scheduler:

```ruby
# Run daily at 4:00 PM IST (after market close)
every 1.day, at: '4:00 pm' do
  runner "Candles::DailyIngestorJob.perform_later"
end
```

**Option 2: Manual Daily Sync**

```ruby
# Via Rails console
rails runner "Candles::DailyIngestor.call"

# Or via background job
Candles::DailyIngestorJob.perform_later
```

**What happens:**
- Fetches only new candles (from latest candle date + 1 day to yesterday)
- Skips instruments already up-to-date
- Typically processes only 1-2 new candles per instrument
- Fast execution (~5-10 minutes for 5000 instruments)

### 3.2 Weekly Candle Sync

Weekly candles should be synced after daily candles (they depend on daily candles).

**Option 1: Scheduled Job**

```ruby
# Run daily at 4:15 PM IST (after daily sync)
every 1.day, at: '4:15 pm' do
  runner "Candles::WeeklyIngestorJob.perform_later"
end
```

**Option 2: Manual Daily Sync**

```ruby
# Via Rails console
rails runner "Candles::WeeklyIngestor.call"

# Or via background job
Candles::WeeklyIngestorJob.perform_later
```

**What happens:**
- Aggregates new daily candles into weekly candles
- Only processes weeks that have new daily data
- Very fast execution (~1-2 minutes for 5000 instruments)

### 3.3 Hourly Candle Sync

Hourly candles are typically fetched on-demand during trading hours. For daily sync:

```ruby
# Fetch last 24 hours of hourly candles
instruments = Instrument.where(segment: %w[equity index])
instruments.find_each do |instrument|
  Candles::IntradayFetcher.call(
    instrument: instrument,
    interval: '60',
    days: 1  # Last 1 day = ~6-7 hours of trading
  )
end
```

---

## Handling Missing Data

### 4.1 Detect Missing Candles

```ruby
# Check for instruments with insufficient daily candles (< 365)
instruments = Instrument.where(segment: %w[equity index])
instruments.find_each do |instrument|
  count = CandleSeriesRecord.daily.where(instrument: instrument).count
  if count < 365
    latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: :daily)
    latest_date = latest ? latest.timestamp.to_date : nil
    puts "#{instrument.symbol_name}: #{count} candles (latest: #{latest_date})"
  end
end

# Check for gaps in daily candles
instrument = Instrument.find_by(symbol_name: 'RELIANCE')
candles = CandleSeriesRecord.daily.where(instrument: instrument).order(:timestamp)
dates = candles.pluck(:timestamp).map(&:to_date)
expected_dates = (dates.min..dates.max).select { |d| (1..5).include?(d.wday) } # Weekdays only
missing_dates = expected_dates - dates
puts "Missing dates: #{missing_dates.first(10)}"
```

### 4.2 Fill Missing Data

```ruby
# Re-ingest for specific instrument with extended date range
instrument = Instrument.find_by(symbol_name: 'RELIANCE')

# Fetch more days to fill gaps
Candles::DailyIngestor.call(
  instruments: [instrument],
  days_back: 730  # 2 years to ensure we get 365+ candles
)

# For weekly candles, ensure daily candles exist first
Candles::DailyIngestor.call(instruments: [instrument], days_back: 730)
Candles::WeeklyIngestor.call(instruments: [instrument], weeks_back: 104)  # 2 years
```

### 4.3 Handle Instruments with No Data

```ruby
# Find instruments with no candles
instruments_without_candles = Instrument
  .where(segment: %w[equity index])
  .left_joins(:candle_series_records)
  .where(candle_series_records: { id: nil })
  .distinct

puts "Instruments without candles: #{instruments_without_candles.count}"

# Try to ingest for these instruments
Candles::DailyIngestor.call(instruments: instruments_without_candles, days_back: 365)

# Check for instruments that failed
failed_instruments = instruments_without_candles.select do |instrument|
  CandleSeriesRecord.daily.where(instrument: instrument).count.zero?
end

# Common reasons for failure:
# - Invalid security_id
# - Instrument delisted/suspended
# - API rate limits
# - Network issues
```

---

## Verification & Monitoring

### 5.1 Verify Minimum Candle Requirements

```ruby
# Verify all instruments have minimum 365 daily candles
instruments = Instrument.where(segment: %w[equity index])
insufficient = []

instruments.find_each do |instrument|
  daily_count = CandleSeriesRecord.daily.where(instrument: instrument).count
  weekly_count = CandleSeriesRecord.weekly.where(instrument: instrument).count
  hourly_count = CandleSeriesRecord.hourly.where(instrument: instrument).count
  
  if daily_count < 365 || weekly_count < 52 || hourly_count < 365
    insufficient << {
      symbol: instrument.symbol_name,
      daily: daily_count,
      weekly: weekly_count,
      hourly: hourly_count
    }
  end
end

puts "Instruments with insufficient candles: #{insufficient.count}"
insufficient.first(10).each do |item|
  puts "#{item[:symbol]}: Daily=#{item[:daily]}, Weekly=#{item[:weekly]}, Hourly=#{item[:hourly]}"
end
```

### 5.2 Check Candle Freshness

```ruby
# Check freshness using FreshnessChecker
daily_freshness = Candles::FreshnessChecker.check_freshness(timeframe: :daily)
puts "Daily candles: #{daily_freshness[:freshness_percentage].round(1)}% fresh"

weekly_freshness = Candles::FreshnessChecker.check_freshness(timeframe: :weekly)
puts "Weekly candles: #{weekly_freshness[:freshness_percentage].round(1)}% fresh"

# Auto-ingest if stale
Candles::FreshnessChecker.ensure_fresh(timeframe: :daily, auto_ingest: true)
Candles::FreshnessChecker.ensure_fresh(timeframe: :weekly, auto_ingest: true)
```

### 5.3 Monitor via Health Checks

The `MonitorJob` automatically checks candle freshness:

```ruby
# Run health check
MonitorJob.perform_now

# Check results
result = MonitorJob.perform_now
puts result[:candle_freshness]
```

---

## Troubleshooting

### 6.1 Rate Limiting

If you hit API rate limits:

```ruby
# Increase delay between requests
# Edit config/algo.yml or set environment variable
# dhanhq:
#   candle_ingestion_delay_seconds: 1.0  # Increase from 0.5 to 1.0
#   candle_ingestion_delay_interval: 3  # Apply delay every 3 requests instead of 5

# Or pass custom config
AlgoConfig.fetch[:dhanhq][:candle_ingestion_delay_seconds] = 1.0
Candles::DailyIngestor.call
```

### 6.2 Missing Security IDs

```ruby
# Find instruments without security_id
Instrument.where(segment: %w[equity index]).where(security_id: nil).count

# Re-import instruments to get security_id
InstrumentsImporter.import_from_url
```

### 6.3 Incomplete Data

```ruby
# Check for instruments with gaps
instrument = Instrument.find_by(symbol_name: 'RELIANCE')
candles = CandleSeriesRecord.daily.where(instrument: instrument).order(:timestamp)

# Check date range
puts "First candle: #{candles.first.timestamp.to_date}"
puts "Last candle: #{candles.last.timestamp.to_date}"
puts "Total candles: #{candles.count}"

# Re-ingest with extended range
Candles::DailyIngestor.call(instruments: [instrument], days_back: 730)
```

### 6.4 Weekly Candles Not Updating

Weekly candles depend on daily candles. If weekly candles aren't updating:

```ruby
# Ensure daily candles are up-to-date first
Candles::DailyIngestor.call

# Then update weekly candles
Candles::WeeklyIngestor.call
```

---

## Quick Reference Commands

### Initial Setup (One-Time)

```bash
# 1. Import instruments
rails runner "InstrumentsImporter.import_from_url"

# 2. Ingest daily candles (365 days)
rails runner "Candles::DailyIngestor.call"

# 3. Ingest weekly candles (52 weeks)
rails runner "Candles::WeeklyIngestor.call"

# 4. Verify minimum candles
rails runner "
  instruments = Instrument.where(segment: %w[equity index])
  instruments.find_each do |i|
    daily = CandleSeriesRecord.daily.where(instrument: i).count
    weekly = CandleSeriesRecord.weekly.where(instrument: i).count
    puts \"#{i.symbol_name}: Daily=#{daily}, Weekly=#{weekly}\" if daily < 365 || weekly < 52
  end
"
```

### Daily Sync (Run Daily)

```bash
# 1. Sync daily candles
rails runner "Candles::DailyIngestor.call"

# 2. Sync weekly candles (after daily)
rails runner "Candles::WeeklyIngestor.call"

# 3. Check freshness
rails runner "puts Candles::FreshnessChecker.check_freshness(timeframe: :daily)"
```

### Background Jobs

```ruby
# Schedule daily sync
Candles::DailyIngestorJob.perform_later
Candles::WeeklyIngestorJob.perform_later

# Or schedule via cron/whenever
# config/schedule.rb:
every 1.day, at: '4:00 pm' do
  runner "Candles::DailyIngestorJob.perform_later"
end

every 1.day, at: '4:15 pm' do
  runner "Candles::WeeklyIngestorJob.perform_later"
end
```

---

## Summary

1. **Import Instruments**: `InstrumentsImporter.import_from_url`
2. **Initial Daily Candles**: `Candles::DailyIngestor.call` (365 days)
3. **Initial Weekly Candles**: `Candles::WeeklyIngestor.call` (52 weeks)
4. **Initial Hourly Candles**: `Candles::IntradayFetcher.call` (15 days for ~365 hours)
5. **Daily Sync**: Run `DailyIngestor` and `WeeklyIngestor` daily after market close
6. **Monitor**: Use `MonitorJob` and `FreshnessChecker` to ensure data freshness

All services handle:
- ✅ Rate limiting
- ✅ Retry logic
- ✅ Incremental updates (only fetch new data)
- ✅ Missing data detection
- ✅ Progress logging
- ✅ Error handling
