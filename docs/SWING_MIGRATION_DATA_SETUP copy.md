# 📊 SwingLongTrader Data Setup & Population Files

**Complete guide for data population, importers, and setup scripts needed for SwingLongTrader**

---

## Table of Contents

1. [Core Data Setup Files](#core-data-setup-files)
2. [Models Required for Data](#models-required-for-data)
3. [Importers & Services](#importers--services)
4. [Rake Tasks](#rake-tasks)
5. [Seed Files](#seed-files)
6. [Setup Scripts](#setup-scripts)
7. [Migration Notes](#migration-notes)

---

## Core Data Setup Files

### ✅ MUST COPY - Core Importer

| File                                   | Purpose                                            | Copy?     | Notes                                    |
| -------------------------------------- | -------------------------------------------------- | --------- | ---------------------------------------- |
| `app/services/instruments_importer.rb` | **CRITICAL** - Imports instruments from DhanHQ CSV | ✅ **YES** | Core importer, needed for all data setup |

**What it does:**
- Downloads CSV from DhanHQ API: `https://images.dhan.co/api-data/api-scrip-master-detailed.csv`
- Parses CSV and splits into instruments vs derivatives
- Uses `activerecord-import` for bulk upserts
- Caches CSV locally (24-hour cache)
- Records import statistics in Settings table

**Key Features:**
- Handles both instruments (EQUITY, INDEX) and derivatives (OPTIONS, FUTURES)
- Upsert logic (adds new, updates existing)
- Batch processing (1000 records per batch)
- Error handling with fallback to cached CSV

---

## Models Required for Data

### ✅ MUST COPY - Data Models

| Model                                   | Purpose                                     | Copy?     | Notes                            |
| --------------------------------------- | ------------------------------------------- | --------- | -------------------------------- |
| `app/models/instrument.rb`              | Master instrument data                      | ✅ **YES** | Already in migration guide       |
| `app/models/setting.rb`                 | Key-value settings storage                  | ✅ **YES** | Used by importer for tracking    |
| `app/models/instrument_type_mapping.rb` | Maps instrument types (INDEX→FUTIDX/OPTIDX) | ✅ **YES** | Used by importer for derivatives |

### ⚠️ OPTIONAL - Derivative Model

| Model                      | Purpose                   | Copy?          | Notes                                     |
| -------------------------- | ------------------------- | -------------- | ----------------------------------------- |
| `app/models/derivative.rb` | Options/Futures contracts | ⚠️ **OPTIONAL** | Only if trading options/futures for swing |

**Decision:**
- **For Swing Trading Stocks:** Can skip `Derivative` model
- **For Swing Trading Options:** Copy `Derivative` model and related logic

---

## Importers & Services

### 1. InstrumentsImporter Service

**File:** `app/services/instruments_importer.rb`

**Copy:** ✅ **YES** (with modifications)

**Modifications needed for SwingLongTrader:**

```ruby
# Remove derivative import logic if not trading options
# Keep only instrument import for stock trading

# Option 1: Keep both (if trading options)
# - Keep as-is

# Option 2: Stocks only (simplified)
# - Remove derivative import methods
# - Remove attach_instrument_ids method
# - Simplify build_batches to return only instruments
```

**Key Methods:**
- `import_from_url` - Main entry point, downloads CSV and imports
- `fetch_csv_with_cache` - Downloads CSV with 24-hour cache
- `import_from_csv(csv_content)` - Parses and imports CSV
- `build_batches(csv_content)` - Splits CSV into instruments/derivatives
- `import_instruments!(rows)` - Bulk upsert instruments
- `import_derivatives!(rows)` - Bulk upsert derivatives (if needed)
- `record_success!(summary)` - Records import stats in Settings

**Dependencies:**
- `Instrument` model
- `Derivative` model (if trading options)
- `Setting` model
- `InstrumentTypeMapping` module
- `activerecord-import` gem

---

## Rake Tasks

### ✅ MUST COPY - Instrument Import Tasks

**File:** `lib/tasks/instruments.rake`

**Copy:** ✅ **YES** (with modifications)

**Key Tasks:**

1. **`instruments:import`** - Main import task
   ```bash
   rails instruments:import
   ```
   - Downloads CSV from DhanHQ
   - Imports instruments and derivatives
   - Shows statistics

2. **`instruments:reimport`** - Reimport (upsert mode)
   ```bash
   rails instruments:reimport
   ```
   - Safe reimport (adds new, updates existing)
   - Does not delete existing records

3. **`instruments:status`** - Check import freshness
   ```bash
   rails instruments:status
   ```
   - Shows last import time
   - Shows import statistics
   - Warns if import is stale (>24 hours)

4. **`instruments:clear`** - Clear all (DANGER)
   ```bash
   rails instruments:clear[true]  # Force mode
   ```
   - Deletes all instruments/derivatives
   - Only use for complete reset

**Modifications for SwingLongTrader:**

```ruby
# Remove derivative-related stats if not trading options
# Simplify status output for stocks-only trading
```

### ✅ OPTIONAL - Test Environment Tasks

**File:** `lib/tasks/instruments.rake` (test namespace)

**Copy:** ⚠️ **OPTIONAL** (for testing)

**Key Tasks:**

1. **`test:instruments:import`** - Import for test environment
   ```bash
   RAILS_ENV=test rails test:instruments:import
   ```
   - Uses cached CSV if available
   - Supports filtered CSV for faster tests

2. **`test:instruments:filter_csv`** - Create filtered CSV
   ```bash
   RAILS_ENV=test rails test:instruments:filter_csv
   ```
   - Filters CSV to only NIFTY, BANKNIFTY, SENSEX
   - Speeds up test imports

---

## Seed Files

### ✅ MUST COPY - Database Seeds

**File:** `db/seeds.rb`

**Copy:** ✅ **YES** (with heavy modifications)

**Current AlgoScalperAPI seeds:**
- Seeds watchlist items for NIFTY, BANKNIFTY, SENSEX
- Requires instruments to be imported first
- Uses `WatchlistItem` model (scalper-specific)

**Modifications for SwingLongTrader:**

```ruby
# db/seeds.rb for SwingLongTrader
# frozen_string_literal: true

# Option 1: Minimal seeds (no watchlist needed)
# - Just verify instruments are imported

# Option 2: Swing watchlist (if needed)
# - Create watchlist for swing trading universe
# - Different from scalper watchlist

# Example minimal seeds:
if Instrument.count.zero?
  puts "⚠️  No instruments found. Run: rails instruments:import"
else
  puts "✅ Instruments ready: #{Instrument.count} total"
  puts "   NSE: #{Instrument.nse.count}"
  puts "   BSE: #{Instrument.bse.count}"
end
```

---

## Setup Scripts

### ✅ OPTIONAL - Bin Setup

**File:** `bin/setup`

**Copy:** ⚠️ **OPTIONAL** (standard Rails setup script)

**Current content:**
- Installs dependencies
- Prepares database
- Clears logs/temp files
- Starts dev server

**Modifications for SwingLongTrader:**

```ruby
# bin/setup
#!/usr/bin/env ruby
require "fileutils"

APP_ROOT = File.expand_path("..", __dir__)

def system!(*args)
  system(*args, exception: true)
end

FileUtils.chdir APP_ROOT do
  puts "== Installing dependencies =="
  system("bundle check") || system!("bundle install")

  puts "\n== Preparing database =="
  system! "bin/rails db:prepare"

  puts "\n== Importing instruments =="
  puts "   Run 'rails instruments:import' to import instruments"
  puts "   (This may take a few minutes)"

  puts "\n== Removing old logs and tempfiles =="
  system! "bin/rails log:clear tmp:clear"

  unless ARGV.include?("--skip-server")
    puts "\n== Starting development server =="
    STDOUT.flush
    exec "bin/dev"
  end
end
```

---

## Database Migrations

### ✅ MUST CREATE - Settings Table

**Migration:** `db/migrate/YYYYMMDDHHMMSS_create_settings.rb`

**Copy structure from AlgoScalperAPI:**

```ruby
# frozen_string_literal: true

class CreateSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :settings do |t|
      t.string :key,   null: false
      t.text   :value, null: true

      t.timestamps
    end
    add_index :settings, :key, unique: true
  end
end
```

**Why needed:**
- InstrumentsImporter stores import statistics here
- Used for tracking last import time, counts, etc.
- General key-value storage for app settings

---

## Complete File List

### ✅ Files to Copy

```
app/services/
├── instruments_importer.rb          # ✅ COPY (modify for stocks-only if needed)

app/models/
├── instrument.rb                     # ✅ COPY (already in guide)
├── setting.rb                        # ✅ COPY (NEW - needed for importer)
├── instrument_type_mapping.rb       # ✅ COPY (NEW - used by importer)
└── derivative.rb                     # ⚠️ OPTIONAL (only if trading options)

lib/tasks/
└── instruments.rake                  # ✅ COPY (modify derivative stats if needed)

db/
├── seeds.rb                          # ✅ COPY (heavily modify)
└── migrate/
    └── YYYYMMDDHHMMSS_create_settings.rb  # ✅ CREATE (new migration)

bin/
└── setup                             # ⚠️ OPTIONAL (standard Rails script)
```

---

## Setup Workflow

### Step-by-Step Data Setup

```bash
# 1. Create new Rails app
rails new swing_long_trader --api -d postgresql
cd swing_long_trader

# 2. Copy required files
# (See file list above)

# 3. Install gems
bundle install

# 4. Run migrations
rails db:create
rails db:migrate

# 5. Import instruments
rails instruments:import

# 6. Verify import
rails instruments:status

# 7. Run seeds (optional)
rails db:seed
```

---

## Import Process Details

### What Gets Imported

**From DhanHQ CSV:**
- **Instruments:** Stocks, Indices (NIFTY, BANKNIFTY, SENSEX, etc.)
- **Derivatives:** Options, Futures (if copying derivative logic)

**CSV Source:**
- URL: `https://images.dhan.co/api-data/api-scrip-master-detailed.csv`
- Cached locally: `tmp/dhan_scrip_master.csv`
- Cache duration: 24 hours

**Import Statistics:**
- Stored in `settings` table:
  - `instruments.last_imported_at`
  - `instruments.last_import_duration_sec`
  - `instruments.last_instrument_rows`
  - `instruments.last_derivative_rows`
  - `instruments.instrument_total`
  - `instruments.derivative_total`

---

## Modifications for Swing Trading

### Option 1: Stocks Only (Simplified)

**Changes to `instruments_importer.rb`:**

```ruby
# Remove derivative import logic
def import_from_csv(csv_content)
  instruments_rows = build_batches(csv_content)

  instrument_import = import_instruments!(instruments_rows)

  {
    instrument_rows: instruments_rows.size,
    instrument_upserts: instrument_import&.ids&.size.to_i,
    instrument_total: Instrument.count
  }
end

def build_batches(csv_content)
  instruments = []

  CSV.parse(csv_content, headers: true).each do |row|
    next unless VALID_EXCHANGES.include?(row['EXCH_ID'])
    next if row['SEGMENT'] == 'D'  # Skip derivatives

    attrs = build_attrs(row)
    instruments << attrs.slice(*Instrument.column_names.map(&:to_sym))
  end

  instruments
end

# Remove import_derivatives! method
# Remove attach_instrument_ids method
```

**Changes to `instruments.rake`:**

```ruby
# Remove derivative stats from output
pp "Total Instruments: #{result[:instrument_total]}"
pp "NSE Instruments: #{Instrument.nse.count}"
pp "BSE Instruments: #{Instrument.bse.count}"
# Remove derivative-related stats
```

### Option 2: Stocks + Options (Full Copy)

**Keep everything as-is:**
- Copy full `instruments_importer.rb`
- Copy `Derivative` model
- Copy derivative import logic
- Keep all rake task stats

---

## Testing Setup

### Test Environment Import

**For faster test imports:**

```bash
# 1. Create filtered CSV (only NIFTY, BANKNIFTY, SENSEX)
RAILS_ENV=test rails test:instruments:filter_csv

# 2. Import using filtered CSV
FILTERED_CSV=true RAILS_ENV=test rails test:instruments:import

# 3. Check status
RAILS_ENV=test rails test:instruments:status
```

**Auto-import in tests:**

```ruby
# spec/support/database_cleaner.rb
# Add auto-import after truncation
if ENV['AUTO_IMPORT_INSTRUMENTS'] == 'true'
  InstrumentsImporter.import_from_url
end
```

---

## Verification Checklist

### After Setup

- [ ] `Setting` model exists and works
- [ ] `InstrumentTypeMapping` module loads
- [ ] `InstrumentsImporter` service loads
- [ ] Rake tasks are available: `rails -T instruments`
- [ ] Import works: `rails instruments:import`
- [ ] Status check works: `rails instruments:status`
- [ ] Settings table has import statistics
- [ ] Instruments table has data
- [ ] Seeds run without errors (if using)

---

## Common Issues

### Issue: CSV Download Fails

**Solution:**
```bash
# Check network connectivity
# CSV is cached, so can use cached version
# Check DhanHQ API status
```

### Issue: Import Takes Too Long

**Solution:**
```bash
# Use filtered CSV for testing
# Increase BATCH_SIZE in importer (if needed)
# Import in background job (future enhancement)
```

### Issue: Derivative Import Fails

**Solution:**
```bash
# If trading stocks only, remove derivative logic
# If trading options, ensure Derivative model exists
# Check instrument_id references are valid
```

---

## Next Steps

After data setup:

1. ✅ Verify instruments are imported
2. ✅ Set up candle ingestion (daily/weekly)
3. ✅ Configure screener to use imported instruments
4. ✅ Test screener with real instrument data
5. ✅ Set up AI ranking with instrument context

---

## Summary

### Critical Files (Must Copy)

1. **`app/services/instruments_importer.rb`** - Core importer
2. **`app/models/setting.rb`** - Settings storage
3. **`app/models/instrument_type_mapping.rb`** - Type mapping
4. **`lib/tasks/instruments.rake`** - Import tasks
5. **`db/migrate/..._create_settings.rb`** - Settings table

### Optional Files

1. **`app/models/derivative.rb`** - Only if trading options
2. **`db/seeds.rb`** - Modify for swing trading
3. **`bin/setup`** - Standard Rails script

### Workflow

1. Copy files
2. Run migrations
3. Import instruments: `rails instruments:import`
4. Verify: `rails instruments:status`
5. Proceed with candle ingestion setup

---

**Last Updated:** Based on AlgoScalperAPI codebase analysis

