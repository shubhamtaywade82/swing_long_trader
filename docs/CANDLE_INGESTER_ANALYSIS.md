# Candle Ingester Implementation Analysis

## Overview
This document analyzes how daily and weekly candles are ingested, focusing on how the system handles:
1. Initial ingestion (no candles available)
2. Incremental updates (when last candle exists)
3. Deduplication to prevent re-inserting existing candles

## Daily Candle Ingester (`DailyIngestor`)

### When No Candles Available
- **Location**: `app/services/candles/daily_ingestor.rb:118-121`
- **Behavior**: Fetches full range from `to_date - @days_back.days` (default: 365 days back)
- **Code**:
  ```ruby
  from_date = to_date - @days_back.days
  ```

### When Last Daily Candle Exists
- **Location**: `app/services/candles/daily_ingestor.rb:92-117`
- **Behavior**:
  1. Finds latest candle using `CandleSeriesRecord.latest_for(instrument: instrument, timeframe: "1D")`
  2. Calculates `from_date = latest_date + 1.day` (next day after latest candle)
  3. Checks if already up-to-date: if `from_date > to_date`, skips the instrument
  4. **ISSUE**: Ensures minimum range with `from_date = [from_date, min_from_date].min`
     - This can cause fetching old candles unnecessarily when latest candle is recent
     - Example: If latest is 2024-06-01 and min_from_date is 2023-12-30, it fetches from 2023-12-30 instead of 2024-06-02

### Deduplication Logic
- **Location**: `app/services/candles/ingestor.rb:52-89`
- **Method**: `upsert_single_candle`
- **Behavior**:
  - For daily candles, uses range query: `timestamp: day_start..day_end` to find existing candles
  - If candle exists and data changed: updates the record
  - If candle exists and data same: skips (returns `{ skipped: true }`)
  - If candle doesn't exist: creates new record
- **Protection**: Database unique constraint on `[instrument_id, timeframe, timestamp]` ensures no duplicates

## Weekly Candle Ingester (`WeeklyIngestor`)

### When No Weekly Candles Available
- **Location**: `app/services/candles/weekly_ingestor.rb:109-111`
- **Behavior**: Fetches full range from `to_date - (@weeks_back * 7).days` (default: 52 weeks back)
- **Code**:
  ```ruby
  from_date = to_date - (@weeks_back * 7).days
  ```

### When Last Weekly Candle Exists
- **Location**: `app/services/candles/weekly_ingestor.rb:77-108`
- **Behavior**:
  1. Finds latest weekly candle using `CandleSeriesRecord.latest_for(instrument: instrument, timeframe: "1W")`
  2. Calculates `from_date` as start of next week after latest weekly candle
  3. Checks if already up-to-date: if latest week is current week or later, skips
  4. **ISSUE**: Same minimum range logic as daily ingester (line 108)
     - Uses `from_date = [from_date, min_from_date].min` which can cause unnecessary fetching

### Data Source
- **Location**: `app/services/candles/weekly_ingestor.rb:151-186`
- **Behavior**: 
  - Loads daily candles from database (NOT from API) using `instrument.load_daily_candles`
  - Aggregates daily candles to weekly using `aggregate_to_weekly` method
  - Groups by week (Monday to Sunday) and aggregates OHLCV data

### Deduplication Logic
- **Location**: `app/services/candles/ingestor.rb:52-89`
- **Method**: Same `upsert_single_candle` method as daily candles
- **Behavior**: Uses exact timestamp match (normalized to beginning_of_week) to find existing candles

## Issues Identified

### Issue 1: Inefficient Date Range Calculation
**Location**: 
- `app/services/candles/daily_ingestor.rb:117`
- `app/services/candles/weekly_ingestor.rb:108`

**Problem**: 
```ruby
from_date = [from_date, min_from_date].min
```

This logic causes unnecessary fetching of old candles when the latest candle is recent. It should only apply the minimum range when there's a gap (latest candle is very old).

**Example**:
- Latest candle: 2024-06-01
- Today: 2024-12-31
- Calculated from_date: 2024-06-02 (latest + 1 day)
- min_from_date: 2023-12-30 (to_date - 365 days)
- Result: Fetches from 2023-12-30 (unnecessary, includes existing candles)

**Expected Behavior**:
- If latest candle is recent (within days_back), fetch from `latest_date + 1.day`
- If latest candle is old (older than min_from_date), fetch from `min_from_date` to fill gaps

### Issue 2: Weekly Ingestor Dependency
The weekly ingestor depends on daily candles being available in the database. If daily candles are missing for a date range, weekly candles cannot be computed for that period.

## Recommendations

1. **Fix Date Range Logic**: Only apply minimum range when latest candle is older than min_from_date
2. **Add Validation**: Ensure daily candles exist before computing weekly candles
3. **Add Logging**: Log when minimum range is applied vs when incremental update is used
4. **Consider Gap Detection**: Detect gaps in candle data and handle them separately
