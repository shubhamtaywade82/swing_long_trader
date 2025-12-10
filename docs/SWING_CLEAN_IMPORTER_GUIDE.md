# 🧹 Clean Instrument Importer Guide for SwingLongTrader

**Complete guide for cleaning the importer to only import NSE stocks from index constituents**

---

## Table of Contents

1. [Overview](#overview)
2. [What to Remove](#what-to-remove)
3. [What to Keep](#what-to-keep)
4. [NSE Index Universe Setup](#nse-index-universe-setup)
5. [Cleaned Importer Implementation](#cleaned-importer-implementation)
6. [Watchlist Modifications](#watchlist-modifications)
7. [Rake Tasks](#rake-tasks)
8. [Verification](#verification)

---

## Overview

### Goal
Create a **clean, NSE-stocks-only importer** that:
- Imports ONLY NSE equity stocks
- Filters to stocks appearing in ANY NSE index
- Removes ALL derivatives/options logic
- Removes ALL index instruments
- Removes ALL non-equity instruments
- Creates a clean universe of ~1,000-1,300 quality stocks

### Key Principles
- ✅ **Import**: Only NSE_EQ segment stocks
- ✅ **Filter**: Only stocks in NSE index constituents
- ❌ **Remove**: All derivatives, options, futures, indices
- ❌ **Remove**: All non-equity instruments
- 🎯 **Result**: Clean universe perfect for swing/long-term trading

---

## What to Remove

### From InstrumentsImporter

**Remove these methods:**
- `import_derivatives!(rows)` - Entire method
- `attach_instrument_ids(rows)` - Derivative parent linking
- Derivative-related logic in `build_batches`
- Derivative statistics in `record_success!`

**Remove these constants:**
- Derivative-related batch processing
- Derivative-related CSV parsing

**Remove from `build_batches`:**
- Derivative array building
- Derivative row processing
- Return only instruments array

**Remove from `import_from_csv`:**
- Derivative import call
- Derivative statistics tracking

### From Instrument Model

**Remove associations:**
```ruby
# REMOVE:
has_many :derivatives, dependent: :destroy
accepts_nested_attributes_for :derivatives
```

**Keep associations:**
```ruby
# KEEP:
has_many :watchlist_items, as: :watchable
has_many :candle_series
```

### From WatchlistItem Model

**Remove derivative-related:**
```ruby
# REMOVE:
def derivative
  watchable if watchable_type == 'Derivative'
end

# REMOVE from enum:
derivative: 2,
```

**Keep:**
```ruby
# KEEP:
def instrument
  watchable if watchable_type == 'Instrument'
end

# KEEP in enum:
equity: 1,
```

---

## What to Keep

### Core Importer Logic

✅ **Keep:**
- CSV download and caching
- CSV parsing
- Instrument attribute building
- Instrument upsert logic
- Settings tracking
- Error handling
- Batch processing

### Core Models

✅ **Keep:**
- `Instrument` model (with derivatives removed)
- `WatchlistItem` model (with derivatives removed)
- `Setting` model
- `InstrumentTypeMapping` (if used, but simplify)

---

## NSE Index Universe Setup

### Step 1: Create Universe Directory Structure

```
config/universe/
├── csv/
│   ├── nifty50.csv
│   ├── nifty100.csv
│   ├── nifty200.csv
│   ├── nifty500.csv
│   ├── midcap100.csv
│   ├── smallcap100.csv
│   └── sectors/
│       ├── nifty_bank.csv
│       ├── nifty_it.csv
│       └── ... (other sector indices)
└── master_universe.yml  # Generated file
```

### Step 2: Download NSE Index CSVs

**NSE Index CSV URLs:**

```
https://www.niftyindices.com/IndexConstituent/ind_nifty50list.csv
https://www.niftyindices.com/IndexConstituent/ind_nifty100list.csv
https://www.niftyindices.com/IndexConstituent/ind_nifty200list.csv
https://www.niftyindices.com/IndexConstituent/ind_nifty500list.csv
https://www.niftyindices.com/IndexConstituent/ind_niftymidcap100list.csv
https://www.niftyindices.com/IndexConstituent/ind_niftysmallcap100list.csv
```

**Sector indices:**
```
https://www.niftyindices.com/IndexConstituent/ind_niftybanklist.csv
https://www.niftyindices.com/IndexConstituent/ind_niftyitlist.csv
https://www.niftyindices.com/IndexConstituent/ind_niftyfmcglist.csv
https://www.niftyindices.com/IndexConstituent/ind_niftypharmalist.csv
https://www.niftyindices.com/IndexConstituent/ind_niftyautolist.csv
... (and all other sector indices)
```

**Download script:**
```bash
# Save to config/universe/csv/
curl -o config/universe/csv/nifty50.csv "https://www.niftyindices.com/IndexConstituent/ind_nifty50list.csv"
curl -o config/universe/csv/nifty100.csv "https://www.niftyindices.com/IndexConstituent/ind_nifty100list.csv"
# ... repeat for all indices
```

### Step 3: Build Master Universe

**Rake task:** `lib/tasks/universe.rake`

```ruby
# frozen_string_literal: true

namespace :universe do
  desc 'Build master universe from all NSE index CSVs'
  task build: :environment do
    require 'csv'

    csv_dir = Rails.root.join('config/universe/csv')
    csv_files = Dir[csv_dir.join('**/*.csv')]

    if csv_files.empty?
      puts "❌ No CSV files found in #{csv_dir}"
      puts "   Download NSE index CSVs first"
      exit 1
    end

    symbols = []
    csv_files.each do |file|
      begin
        CSV.foreach(file, headers: true) do |row|
          # Extract symbol (handle different CSV formats)
          symbol = row['Symbol'] || row['symbol'] || row['SYMBOL']
          next if symbol.blank?

          # Normalize symbol (remove -EQ, -BE suffixes)
          symbol = symbol.strip.upcase
          symbol = symbol.split('-').first if symbol.include?('-')
          symbols << symbol
        end
      rescue StandardError => e
        puts "⚠️  Error reading #{File.basename(file)}: #{e.message}"
      end
    end

    symbols = symbols.compact.uniq.sort

    master_file = Rails.root.join('config/universe/master_universe.yml')
    File.write(master_file, symbols.to_yaml)

    puts "✅ Master universe created: #{symbols.size} unique stocks"
    puts "   Saved to: #{master_file}"
    puts "\n📊 Breakdown:"
    puts "   Total symbols: #{symbols.size}"
  end

  desc 'Show universe statistics'
  task stats: :environment do
    master_file = Rails.root.join('config/universe/master_universe.yml')
    unless master_file.exist?
      puts "❌ Master universe not found. Run: rails universe:build"
      exit 1
    end

    symbols = YAML.load_file(master_file)
    puts "📊 Universe Statistics:"
    puts "   Total stocks: #{symbols.size}"
    puts "   Sample symbols: #{symbols.first(10).join(', ')}"
  end
end
```

---

## Cleaned Importer Implementation

### New InstrumentsImporter (Stocks-Only)

**File:** `app/services/instruments_importer.rb`

```ruby
# frozen_string_literal: true

require 'csv'
require 'open-uri'

class InstrumentsImporter
  CSV_URL = 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv'
  CACHE_PATH = Rails.root.join('tmp/dhan_scrip_master.csv')
  CACHE_MAX_AGE = 24.hours
  VALID_EXCHANGES = %w[NSE].freeze
  BATCH_SIZE = 1_000

  # Load allowed universe from YAML
  UNIVERSE_FILE = Rails.root.join('config/universe/master_universe.yml')
  ALLOWED_SYMBOLS = if UNIVERSE_FILE.exist?
                      YAML.load_file(UNIVERSE_FILE).to_set
                    else
                      Set.new
                    end

  class << self
    def import_from_url
      started_at = Time.current
      csv_text = fetch_csv_with_cache
      summary = import_from_csv(csv_text)

      finished_at = Time.current
      summary[:started_at] = started_at
      summary[:finished_at] = finished_at
      summary[:duration] = finished_at - started_at

      record_success!(summary)
      summary
    end

    def fetch_csv_with_cache
      if CACHE_PATH.exist? && Time.current - CACHE_PATH.mtime < CACHE_MAX_AGE
        return CACHE_PATH.read
      end

      csv_text = URI.open(CSV_URL, &:read) # rubocop:disable Security/Open

      CACHE_PATH.dirname.mkpath
      File.write(CACHE_PATH, csv_text)

      csv_text
    rescue StandardError => e
      raise e unless CACHE_PATH.exist?

      CACHE_PATH.read
    end
    private :fetch_csv_with_cache

    def import_from_csv(csv_content)
      instruments_rows = build_batches(csv_content)

      instrument_import = instruments_rows.empty? ? nil : import_instruments!(instruments_rows)

      {
        instrument_rows: instruments_rows.size,
        instrument_upserts: instrument_import&.ids&.size.to_i,
        instrument_total: Instrument.count
      }
    end

    private

    # Build batches - ONLY instruments, NO derivatives
    def build_batches(csv_content)
      instruments = []

      CSV.parse(csv_content, headers: true).each do |row|
        # Filter 1: Only NSE exchange
        next unless row['EXCH_ID'] == 'NSE'

        # Filter 2: Only equity segment (not derivatives, not indices)
        next unless row['SEGMENT'] == 'E' || row['SEGMENT'] == 'EQ'

        # Filter 3: Extract and normalize symbol
        symbol = row['SYMBOL_NAME']&.strip&.upcase
        next if symbol.blank?

        # Normalize symbol (remove -EQ suffix if present)
        symbol = symbol.split('-').first if symbol.include?('-')

        # Filter 4: Only symbols in NSE index universe
        next unless ALLOWED_SYMBOLS.include?(symbol)

        attrs = build_attrs(row, symbol)
        instruments << attrs.slice(*Instrument.column_names.map(&:to_sym))
      end

      instruments
    end

    def build_attrs(row, normalized_symbol)
      now = Time.zone.now
      {
        security_id: row['SECURITY_ID'],
        exchange: row['EXCH_ID'],
        segment: 'EQ', # Force to EQ for equity
        isin: row['ISIN'],
        instrument_code: row['INSTRUMENT'],
        symbol_name: normalized_symbol,
        display_name: row['DISPLAY_NAME'],
        instrument_type: 'EQUITY',
        series: row['SERIES'],
        lot_size: row['LOT_SIZE']&.to_i,
        tick_size: row['TICK_SIZE']&.to_f,
        created_at: now,
        updated_at: now
      }
    end

    def import_instruments!(rows)
      Instrument.import(
        rows,
        batch_size: BATCH_SIZE,
        on_duplicate_key_update: {
          conflict_target: %i[security_id exchange segment],
          columns: %i[
            display_name isin instrument_code instrument_type
            symbol_name lot_size tick_size updated_at
          ]
        }
      )
    end

    def record_success!(summary)
      Setting.put('instruments.last_imported_at', summary[:finished_at].iso8601)
      Setting.put('instruments.last_import_duration_sec', summary[:duration].to_f.round(2))
      Setting.put('instruments.last_instrument_rows', summary[:instrument_rows])
      Setting.put('instruments.last_instrument_upserts', summary[:instrument_upserts])
      Setting.put('instruments.instrument_total', summary[:instrument_total])
    end
  end
end
```

---

## Watchlist Modifications

### Cleaned WatchlistItem Model

**File:** `app/models/watchlist_item.rb`

```ruby
# frozen_string_literal: true

class WatchlistItem < ApplicationRecord
  belongs_to :watchable, polymorphic: true, optional: true

  validates :segment, presence: true
  validates :security_id, presence: true
  validates :security_id, uniqueness: { scope: :segment }

  # Simplified enum - removed derivative
  enum :kind, {
    equity: 1,
    index_value: 0  # Keep for indices if needed, but we won't use it
  }

  scope :active, -> { where(active: true) }
  scope :by_segment, ->(seg) { where(segment: seg) }
  scope :for, ->(seg, sid) { where(segment: seg, security_id: sid) }
  scope :equity_only, -> { where(kind: :equity) }

  def exchange_segment
    segment
  end

  def exchange_segment=(value)
    self.segment = value
  end

  # Only instrument accessor (derivative removed)
  def instrument
    watchable if watchable_type == 'Instrument'
  end
end
```

### Watchlist Model (if it exists)

**If you have a Watchlist model, simplify it:**

```ruby
# frozen_string_literal: true

class Watchlist < ApplicationRecord
  has_many :watchlist_items, dependent: :destroy
  has_many :instruments, through: :watchlist_items, source: :watchable, source_type: 'Instrument'

  validates :name, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }

  # Convenience methods
  def add_instrument(instrument)
    watchlist_items.find_or_create_by!(
      segment: instrument.exchange_segment,
      security_id: instrument.security_id,
      watchable: instrument,
      kind: :equity
    )
  end

  def remove_instrument(instrument)
    watchlist_items.where(watchable: instrument).destroy_all
  end
end
```

---

## Rake Tasks

### Updated Instruments Rake Task

**File:** `lib/tasks/instruments.rake`

```ruby
# frozen_string_literal: true

require 'pp'

namespace :instruments do
  desc 'Import NSE stocks from index universe'
  task import: :environment do
    # Check if universe file exists
    universe_file = Rails.root.join('config/universe/master_universe.yml')
    unless universe_file.exist?
      puts "❌ Master universe not found: #{universe_file}"
      puts "   Run: rails universe:build"
      exit 1
    end

    pp 'Starting NSE stocks import (index universe only)...'
    start_time = Time.current

    begin
      result = InstrumentsImporter.import_from_url
      duration = result[:duration] || (Time.current - start_time)
      pp "\n✅ Import completed successfully in #{duration.round(2)} seconds!"
      pp "   Rows processed: #{result[:instrument_rows]}"
      pp "   Instruments upserted: #{result[:instrument_upserts]}"
      pp "   Total instruments: #{result[:instrument_total]}"

      pp "\n--- Statistics ---"
      pp "NSE Equity: #{Instrument.where(exchange: 'NSE', segment: 'EQ').count}"
      pp "Active: #{Instrument.where(active: true).count}" if Instrument.column_names.include?('active')
    rescue StandardError => e
      pp "❌ Import failed: #{e.message}"
      pp e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  desc 'Reimport NSE stocks (upsert mode)'
  task reimport: :environment do
    pp 'Starting NSE stocks reimport (upsert mode)...'
    pp 'Note: Uses upsert logic - adds new, updates existing.'
    pp ''
    Rake::Task['instruments:import'].invoke
  end

  desc 'Check instrument import status'
  task status: :environment do
    last_import_raw = Setting.fetch('instruments.last_imported_at')

    unless last_import_raw
      pp '❌ No instrument import recorded yet.'
      pp '   Run: rails instruments:import'
      exit 1
    end

    imported_at = Time.zone.parse(last_import_raw.to_s)
    age_seconds = Time.current - imported_at
    max_age = InstrumentsImporter::CACHE_MAX_AGE

    pp "Last import: #{imported_at}"
    pp "Age: #{age_seconds.round(2)} seconds"
    pp "Duration: #{Setting.fetch('instruments.last_import_duration_sec', 'unknown')} seconds"
    pp "Rows processed: #{Setting.fetch('instruments.last_instrument_rows', '0')}"
    pp "Upserts: #{Setting.fetch('instruments.last_instrument_upserts', '0')}"
    pp "Total instruments: #{Setting.fetch('instruments.instrument_total', '0')}"

    if age_seconds > max_age
      pp "⚠️  Status: STALE (older than #{max_age.inspect})"
      pp "   Run: rails instruments:reimport"
      exit 1
    end

    pp '✅ Status: OK'
  rescue ArgumentError => e
    pp "❌ Failed to parse timestamp: #{e.message}"
    exit 1
  end
end
```

---

## Verification

### After Import

```bash
# 1. Check universe file exists
rails universe:stats

# 2. Import instruments
rails instruments:import

# 3. Verify import
rails instruments:status

# 4. Check counts
rails runner "puts Instrument.count"
rails runner "puts Instrument.where(exchange: 'NSE', segment: 'EQ').count"

# 5. Verify no derivatives
rails runner "puts Instrument.where(segment: 'D').count"  # Should be 0
```

### Expected Results

- ✅ Total instruments: ~1,000-1,300 (NSE index constituents)
- ✅ All instruments: exchange = 'NSE', segment = 'EQ'
- ✅ No derivatives: segment = 'D' count = 0
- ✅ No indices: segment = 'I' count = 0
- ✅ All symbols match master_universe.yml

---

## Summary

### Files Modified

1. **`app/services/instruments_importer.rb`** - Completely rewritten (stocks-only)
2. **`app/models/instrument.rb`** - Remove derivatives associations
3. **`app/models/watchlist_item.rb`** - Remove derivative enum value
4. **`lib/tasks/instruments.rake`** - Simplified (no derivative stats)
5. **`lib/tasks/universe.rake`** - NEW (universe builder)

### Files Created

1. **`config/universe/master_universe.yml`** - Generated whitelist
2. **`config/universe/csv/*.csv`** - NSE index CSVs (downloaded)

### Result

- Clean NSE stocks-only database
- ~1,000-1,300 quality stocks
- Perfect for swing/long-term trading
- No derivatives/options bloat
- Fast, efficient, scalable

---

**Last Updated:** Based on AlgoScalperAPI codebase analysis

