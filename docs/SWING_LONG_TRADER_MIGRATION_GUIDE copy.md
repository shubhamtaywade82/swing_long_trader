# 🚀 SwingLongAlgoTrader Migration Guide

**Complete step-by-step guide for creating a new Swing + Long-Term Trading Monolith from AlgoScalperAPI**

**Last Updated:** Based on AlgoScalperAPI codebase analysis
**Target:** Clean, enterprise-grade Swing/Long-Term trading system without scalping baggage

---

## Table of Contents

1. [Overview](#overview)
2. [What to Copy](#what-to-copy)
3. [What NOT to Copy](#what-not-to-copy)
4. [Step-by-Step Migration](#step-by-step-migration)
5. [Folder Structure](#folder-structure)
6. [Database Migrations](#database-migrations)
7. [Configuration Changes](#configuration-changes)
8. [Dependencies](#dependencies)
9. [Service Architecture](#service-architecture)
10. [Job Pipeline](#job-pipeline)
11. [Testing Strategy](#testing-strategy)
12. [Verification Checklist](#verification-checklist)

---

## Overview

### Goal
Create a **clean, production-ready Swing + Long-Term Trading Monolith** that:
- Reuses core foundation from AlgoScalperAPI
- Eliminates all scalping-specific systems
- Uses DB-backed jobs (SolidQueue)
- Implements clean domain-driven architecture
- Supports daily/weekly candle ingestion + on-demand intraday fetching
- Includes AI-powered screening and ranking

### Key Principles
- ✅ **Copy**: Models, indicators, DhanHQ client, OpenAI client, core utilities
- ❌ **Skip**: WebSocket feeds, scalper logic, tick systems, exit managers, bracket orders
- 🎯 **New**: Swing screener, AI ranker, long-term strategy engine, DB-backed jobs

---

## What to Copy

### 1. Core Models

**Copy these files exactly:**

```
app/models/
├── instrument.rb                    # ✅ COPY - Core instrument model
├── candle_series.rb                 # ✅ COPY - Candle data structure
├── candle.rb                        # ✅ COPY - Individual candle model
└── concerns/
    ├── candle_extension.rb          # ✅ COPY - Candle helper methods
    └── instrument_helpers.rb        # ✅ COPY - Instrument utilities
```

**Migration files to copy:**
```
db/migrate/
├── YYYYMMDDHHMMSS_create_instruments.rb      # ✅ COPY
└── YYYYMMDDHHMMSS_create_candle_series.rb     # ✅ COPY (if exists) or create new
```

### 2. Indicator System

**Copy entire indicators directory:**

```
app/services/indicators/
├── base_indicator.rb                # ✅ COPY - Base interface
├── calculator.rb                    # ✅ COPY - Indicator calculations
├── indicator_factory.rb             # ✅ COPY - Factory pattern
├── threshold_config.rb              # ✅ COPY - Configuration
├── supertrend_indicator.rb          # ✅ COPY - Supertrend
├── supertrend.rb                    # ✅ COPY - Supertrend implementation
├── adx_indicator.rb                 # ✅ COPY - ADX
├── rsi_indicator.rb                 # ✅ COPY - RSI
├── macd_indicator.rb                # ✅ COPY - MACD
├── trend_duration_indicator.rb      # ✅ COPY - Trend duration
└── holy_grail.rb                    # ✅ COPY - If used for swing
```

### 3. DhanHQ Integration

**Copy DhanHQ provider and config:**

```
lib/providers/
└── dhanhq_provider.rb               # ✅ COPY - DhanHQ API wrapper

config/initializers/
└── dhanhq_config.rb                 # ✅ COPY - DhanHQ configuration

app/services/concerns/
└── dhanhq_error_handler.rb         # ✅ COPY - Error handling
```

**Note:** The DhanHQ gem is already in Gemfile, keep it:
```ruby
gem 'DhanHQ', git: 'https://github.com/shubhamtaywade82/dhanhq-client.git', branch: 'main'
```

### 4. Telegram Notifications

**Copy Telegram integration:**

```
lib/
├── telegram_notifier.rb              # ✅ COPY - Main notifier
└── notifications/
    └── telegram_notifier.rb         # ✅ COPY - If exists

config/initializers/
└── telegram_notifier.rb              # ✅ COPY - Configuration
```

### 5. Core Utilities

**Copy application service base:**

```
app/services/
└── application_service.rb            # ✅ COPY - Base service class
```

**Copy core extensions (if they exist):**

```
lib/core_extensions/                  # ✅ COPY - If exists
```

### 6. Configuration System

**Copy configuration loader:**

```
config/
├── algo.yml                          # ✅ COPY - But heavily modify (see below)
└── initializers/
    └── algo_config.rb                # ✅ COPY - Config loader
```

### 7. Options Chain Analyzer (Optional - for option-based swing entries)

**If you want option-based swing entries:**

```
app/services/options/
└── chain_analyzer.rb                 # ✅ COPY - Option chain analysis
```

### 8. SMC Components (Optional - for Smart Money Concepts)

**If you want SMC-based swing strategies:**

```
app/services/smc/                     # ✅ COPY - If exists
```

---

## What NOT to Copy

### ❌ Scalping-Specific Services

**DO NOT COPY these directories:**

```
app/services/
├── live/                             # ❌ SKIP - WebSocket, MarketFeedHub, ActiveCache
├── entries/                          # ❌ SKIP - Scalper entry logic
├── orders/                           # ❌ SKIP - BracketPlacer, scalper orders
├── positions/                        # ❌ SKIP - Position tracking for scalping
├── risk/                             # ❌ SKIP - ExitEngine, TrailingEngine, RiskManager
├── signal/                           # ❌ SKIP - Signal::Scheduler, scalper signals
└── trading/                          # ❌ SKIP - Trading supervisor, scalper logic
```

**DO NOT COPY these files:**

```
app/services/
├── tick_cache.rb                     # ❌ SKIP - Tick-level caching
├── trading_session.rb                # ❌ SKIP - Intraday session management
├── index_config_loader.rb            # ❌ SKIP - If scalper-specific
└── index_instrument_cache.rb         # ❌ SKIP - If scalper-specific
```

### ❌ Scalping-Specific Models

```
app/models/
├── position_tracker.rb               # ❌ SKIP - Scalper position tracking
├── derivative.rb                     # ❌ SKIP - If only for scalping
├── trading_signal.rb                 # ❌ SKIP - If scalper-specific
├── watchlist_item.rb                 # ❌ SKIP - If scalper-specific
└── best_indicator_params.rb          # ❌ SKIP - If scalper-optimized
```

### ❌ Real-Time Systems

```
config/initializers/
├── market_stream.rb                  # ❌ SKIP - WebSocket initialization
├── trading_supervisor.rb             # ❌ SKIP - Scalper supervisor
└── orders_gateway.rb                 # ❌ SKIP - If scalper-specific
```

### ❌ Background Jobs (Scalper-Specific)

```
app/jobs/
├── *_signal_job.rb                  # ❌ SKIP - Scalper signal jobs
├── *_entry_job.rb                   # ❌ SKIP - Scalper entry jobs
├── *_exit_job.rb                    # ❌ SKIP - Scalper exit jobs
└── *_risk_job.rb                    # ❌ SKIP - Scalper risk jobs
```

**Note:** We'll create NEW jobs for swing trading (see Job Pipeline section)

---

## Step-by-Step Migration

### STEP 1: Create New Rails Monolith

```bash
# Create new Rails API app
rails new swing_long_trader --api -d postgresql

cd swing_long_trader

# Install dependencies
bundle install

# Create database
rails db:create
```

### STEP 2: Install Required Gems

**Update `Gemfile` with these gems (copy from AlgoScalperAPI):**

```ruby
# frozen_string_literal: true

source 'https://rubygems.org'

gem 'rails', '~> 8.0.2'
gem 'pg', '~> 1.1'
gem 'puma', '>= 5.0'
gem 'tzinfo-data', platforms: %i[windows jruby]

# Database-backed jobs (CRITICAL - replaces Sidekiq)
gem 'solid_cable'
gem 'solid_cache'
gem 'solid_queue'

# Core dependencies
gem 'concurrent-ruby'
gem 'ruby-technical-analysis'
gem 'technical-analysis'

# Bulk operations
gem 'activerecord-import'

# CSV support
gem 'csv', require: false

# Boot optimization
gem 'bootsnap', require: false

# DhanHQ Ruby client
gem 'DhanHQ', git: 'https://github.com/shubhamtaywade82/dhanhq-client.git', branch: 'main'

# Telegram bot
gem 'telegram-bot-ruby', '~> 0.19'

# CORS
gem 'rack-cors'

group :development, :test do
  gem 'debug', platforms: %i[mri windows], require: 'debug/prelude'
  gem 'brakeman', require: false
  gem 'rubocop', '~> 1.71', require: false
  gem 'rubocop-factory_bot', '~> 2.25', require: false
  gem 'rubocop-performance', '~> 1.21', require: false
  gem 'rubocop-rails', '~> 2.23', require: false
  gem 'rubocop-rspec', '~> 3.0', require: false
  gem 'dotenv-rails'
  gem 'database_cleaner-active_record'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'rspec-rails'
  gem 'shoulda-matchers'
  gem 'simplecov', require: false
  gem 'vcr', require: false
  gem 'webmock', require: false
  gem 'annotate'
end
```

**Install SolidQueue:**

```bash
bundle install
rails g solid_queue:install
rails db:migrate
```

**Configure SolidQueue in `config/application.rb`:**

```ruby
# config/application.rb
module SwingLongTrader
  class Application < Rails::Application
    # ... other config ...

    # Use SolidQueue for background jobs
    config.active_job.queue_adapter = :solid_queue

    # ... other config ...
  end
end
```

### STEP 3: Copy Core Foundation

**Create directory structure:**

```bash
mkdir -p app/models/concerns
mkdir -p app/services/indicators
mkdir -p app/services/candles
mkdir -p app/services/screeners
mkdir -p app/services/strategies/swing
mkdir -p app/services/strategies/long_term
mkdir -p lib/providers
mkdir -p lib/notifications
```

**Copy files (use rsync or manual copy):**

```bash
# From AlgoScalperAPI to swing_long_trader

# Models
cp app/models/instrument.rb swing_long_trader/app/models/
cp app/models/candle_series.rb swing_long_trader/app/models/
cp app/models/candle.rb swing_long_trader/app/models/
cp -r app/models/concerns/* swing_long_trader/app/models/concerns/

# Indicators
cp -r app/services/indicators/* swing_long_trader/app/services/indicators/

# Providers
cp lib/providers/dhanhq_provider.rb swing_long_trader/lib/providers/
cp -r lib/notifications/* swing_long_trader/lib/notifications/ 2>/dev/null || true

# Config
cp config/initializers/dhanhq_config.rb swing_long_trader/config/initializers/
cp config/initializers/algo_config.rb swing_long_trader/config/initializers/
cp config/initializers/telegram_notifier.rb swing_long_trader/config/initializers/ 2>/dev/null || true

# Base service
cp app/services/application_service.rb swing_long_trader/app/services/
```

### STEP 4: Create Database Migrations

**Create instruments migration:**

```bash
rails g migration CreateInstruments
```

**Edit migration (copy structure from AlgoScalperAPI):**

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_instruments.rb
# frozen_string_literal: true

class CreateInstruments < ActiveRecord::Migration[8.0]
  def change
    create_table :instruments do |t|
      t.string :exchange, null: false
      t.string :segment, null: false
      t.string :security_id, null: false
      t.string :isin
      t.string :instrument_code
      t.string :underlying_security_id
      t.string :underlying_symbol
      t.string :symbol_name
      t.string :display_name
      t.string :instrument_type
      t.string :series
      t.integer :lot_size
      t.date :expiry_date
      t.decimal :strike_price, precision: 15, scale: 5
      t.string :option_type
      t.decimal :tick_size
      t.string :expiry_flag
      t.string :bracket_flag
      t.string :cover_flag
      t.string :asm_gsm_flag
      t.string :asm_gsm_category
      t.string :buy_sell_indicator
      t.decimal :buy_co_min_margin_per, precision: 8, scale: 2
      t.decimal :sell_co_min_margin_per, precision: 8, scale: 2
      t.decimal :buy_co_sl_range_max_perc, precision: 8, scale: 2
      t.decimal :sell_co_sl_range_min_perc, precision: 8, scale: 2
      t.decimal :buy_bo_min_margin_per, precision: 8, scale: 2
      t.decimal :sell_bo_min_margin_per, precision: 8, scale: 2
      t.decimal :mtf_leverage, precision: 8, scale: 2

      t.timestamps
    end

    add_index :instruments, :instrument_code
    add_index :instruments, :security_id, unique: true
    add_index :instruments, [:exchange, :segment, :security_id], unique: true
    add_index :instruments, :symbol_name
    add_index :instruments, :underlying_symbol
  end
end
```

**Create candle_series migration:**

```bash
rails g migration CreateCandleSeries
```

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_candle_series.rb
# frozen_string_literal: true

class CreateCandleSeries < ActiveRecord::Migration[8.0]
  def change
    create_table :candle_series do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string :timeframe, null: false  # '1D', '1W', '15', '60', etc.
      t.datetime :timestamp, null: false
      t.decimal :open, precision: 15, scale: 5, null: false
      t.decimal :high, precision: 15, scale: 5, null: false
      t.decimal :low, precision: 15, scale: 5, null: false
      t.decimal :close, precision: 15, scale: 5, null: false
      t.bigint :volume, default: 0

      t.timestamps
    end

    add_index :candle_series, [:instrument_id, :timeframe, :timestamp], unique: true, name: 'index_candle_series_on_instrument_timeframe_timestamp'
    add_index :candle_series, [:instrument_id, :timeframe]
    add_index :candle_series, :timestamp
  end
end
```

**Run migrations:**

```bash
rails db:migrate
```

### STEP 5: Update Configuration

**Create `config/algo.yml` (heavily modified from AlgoScalperAPI):**

```yaml
# config/algo.yml
# Swing + Long-Term Trading Configuration

swing_trading:
  enabled: true
  universe:
    indices:
      - NIFTY
      - BANKNIFTY
      - SENSEX
    stocks: []  # Add stock symbols if trading stocks

  screening:
    min_volume: 1000000  # Minimum daily volume
    min_price: 50       # Minimum price
    max_price: 50000    # Maximum price
    exclude_penny_stocks: true

  indicators:
    - type: supertrend
      enabled: true
      period: 10
      multiplier: 3.0
    - type: adx
      enabled: true
      period: 14
      threshold: 25
    - type: rsi
      enabled: true
      period: 14
    - type: macd
      enabled: true

  strategy:
    confirmation_mode: majority  # all, majority, weighted, any
    min_confidence: 0.7
    trend_filters:
      use_ema20: true
      use_ema50: true
      use_ema200: true

  ai_ranking:
    enabled: true
    model: gpt-4o-mini
    max_candidates: 20
    factors:
      - technical_strength
      - volume_profile
      - trend_alignment
      - risk_reward

long_term_trading:
  enabled: true
  holding_period_days: 30  # Minimum holding period
  rebalance_frequency: weekly  # weekly, monthly

candles:
  daily:
    enabled: true
    fetch_time: "07:30"  # IST
    timeframes:
      - "1D"

  weekly:
    enabled: true
    fetch_time: "07:30"  # IST
    timeframes:
      - "1W"

  intraday:
    enabled: true
    fetch_on_demand: true  # Don't store, fetch when needed
    timeframes:
      - "15"   # 15 minutes
      - "60"   # 1 hour
      - "120"  # 2 hours

notifications:
  telegram:
    enabled: true
    chat_id: <%= ENV['TELEGRAM_CHAT_ID'] %>
    bot_token: <%= ENV['TELEGRAM_BOT_TOKEN'] %>

dhanhq:
  client_id: <%= ENV['DHANHQ_CLIENT_ID'] || ENV['CLIENT_ID'] %>
  access_token: <%= ENV['DHANHQ_ACCESS_TOKEN'] || ENV['ACCESS_TOKEN'] %>
  api_base_url: "https://api.dhan.co"
```

**Update `config/initializers/algo_config.rb` (copy from AlgoScalperAPI, modify for swing):**

```ruby
# config/initializers/algo_config.rb
# frozen_string_literal: true

module AlgoConfig
  CONFIG_PATH = Rails.root.join('config', 'algo.yml')

  def self.fetch(key_path, default = nil)
    config = load_config
    keys = key_path.to_s.split('.')
    result = keys.inject(config) { |hash, key| hash&.dig(key) }
    result.nil? ? default : result
  end

  def self.load_config
    @config ||= begin
      erb = ERB.new(File.read(CONFIG_PATH))
      YAML.safe_load(erb.result, permitted_classes: [Symbol], aliases: true) || {}
    end
  end

  def self.reload!
    @config = nil
    load_config
  end
end
```

### STEP 6: Create New Service Architecture

**See [Service Architecture](#service-architecture) section below for detailed implementation.**

---

## Folder Structure

### Complete Target Structure

```
swing_long_trader/
├── app/
│   ├── controllers/
│   │   └── api/
│   │       └── health_controller.rb
│   ├── jobs/
│   │   ├── candles/
│   │   │   ├── daily_ingestor_job.rb
│   │   │   ├── weekly_ingestor_job.rb
│   │   │   └── intraday_fetcher_job.rb
│   │   ├── screeners/
│   │   │   ├── swing_screener_job.rb
│   │   │   └── ai_ranker_job.rb
│   │   └── strategies/
│   │       ├── swing_analysis_job.rb
│   │       ├── swing_entry_monitor_job.rb
│   │       └── swing_exit_monitor_job.rb
│   ├── models/
│   │   ├── application_record.rb
│   │   ├── instrument.rb
│   │   ├── candle_series.rb
│   │   ├── candle.rb
│   │   └── concerns/
│   │       ├── candle_extension.rb
│   │       └── instrument_helpers.rb
│   └── services/
│       ├── application_service.rb
│       ├── candles/
│       │   ├── daily_ingestor.rb
│       │   ├── weekly_ingestor.rb
│       │   └── intraday_fetcher.rb
│       ├── indicators/
│       │   ├── base_indicator.rb
│       │   ├── calculator.rb
│       │   ├── indicator_factory.rb
│       │   ├── supertrend_indicator.rb
│       │   ├── adx_indicator.rb
│       │   ├── rsi_indicator.rb
│       │   └── macd_indicator.rb
│       ├── screeners/
│       │   ├── swing_screener.rb
│       │   ├── ai_ranker.rb
│       │   └── final_selector.rb
│       ├── strategies/
│       │   ├── swing/
│       │   │   ├── engine.rb
│       │   │   ├── evaluator.rb
│       │   │   ├── notifier.rb
│       │   │   └── executor.rb
│       │   └── long_term/
│       │       ├── engine.rb
│       │       └── evaluator.rb
│       └── concerns/
│           └── dhanhq_error_handler.rb
├── config/
│   ├── algo.yml
│   ├── application.rb
│   ├── database.yml
│   └── initializers/
│       ├── algo_config.rb
│       ├── dhanhq_config.rb
│       ├── telegram_notifier.rb
│       └── solid_queue.rb
├── db/
│   ├── migrate/
│   │   ├── YYYYMMDDHHMMSS_create_instruments.rb
│   │   └── YYYYMMDDHHMMSS_create_candle_series.rb
│   └── schema.rb
├── lib/
│   ├── providers/
│   │   └── dhanhq_provider.rb
│   └── notifications/
│       └── telegram_notifier.rb
└── spec/
    └── (test files mirroring app structure)
```

---

## Database Migrations

### Required Tables

1. **instruments** - Master instrument data
2. **candle_series** - Daily, weekly, and optionally intraday candles

### Migration Checklist

- [ ] Create instruments table with all required indexes
- [ ] Create candle_series table with composite unique index
- [ ] Add indexes for common queries (symbol_name, timeframe, timestamp)
- [ ] Run migrations: `rails db:migrate`
- [ ] Verify schema: `rails db:schema:dump`

---

## Configuration Changes

### Environment Variables

**Required ENV variables:**

```bash
# .env (development)
DHANHQ_CLIENT_ID=your_client_id
DHANHQ_ACCESS_TOKEN=your_access_token
# OR use legacy names
CLIENT_ID=your_client_id
ACCESS_TOKEN=your_access_token

TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=your_chat_id

RAILS_ENV=development
RAILS_LOG_LEVEL=info
```

### Application Configuration

**`config/application.rb` changes:**

```ruby
# config/application.rb
module SwingLongTrader
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true

    # Use SolidQueue for background jobs
    config.active_job.queue_adapter = :solid_queue

    # Time zone
    config.time_zone = 'Asia/Kolkata'

    # CORS
    config.middleware.use Rack::Cors do
      allow do
        origins '*'
        resource '*',
                 headers: :any,
                 methods: %i[get post put patch delete options head]
      end
    end
  end
end
```

---

## Dependencies

### Core Gems (Already Listed in STEP 2)

**Critical dependencies:**
- `solid_queue` - DB-backed job queue (replaces Sidekiq)
- `DhanHQ` - Trading API client
- `telegram-bot-ruby` - Notifications
- `ruby-technical-analysis` - Technical indicators
- `technical-analysis` - Additional indicators
- `activerecord-import` - Bulk operations

### Optional Dependencies

- `openai` gem (if using OpenAI for AI ranking) - Add if needed:
  ```ruby
  gem 'ruby-openai', '~> 7.0'
  ```

---

## Service Architecture

### 1. Candle Ingestion Services

**`app/services/candles/daily_ingestor.rb`:**

```ruby
# frozen_string_literal: true

module Candles
  class DailyIngestor < ApplicationService
    def self.call
      new.call
    end

    def call
      instruments = Instrument.where(instrument_type: 'EQUITY')
      instruments.find_each do |instrument|
        fetch_and_store_daily_candles(instrument)
      end
    end

    private

    def fetch_and_store_daily_candles(instrument)
      # Fetch from DhanHQ
      # Store in candle_series table with timeframe='1D'
    end
  end
end
```

**Similar for `weekly_ingestor.rb` and `intraday_fetcher.rb`**

### 2. Screener Services

**`app/services/screeners/swing_screener.rb`:**

```ruby
# frozen_string_literal: true

module Screeners
  class SwingScreener < ApplicationService
    def self.call
      new.call
    end

    def call
      candidates = []

      Instrument.where(instrument_type: 'EQUITY').find_each do |instrument|
        if passes_filters?(instrument)
          candidates << analyze_instrument(instrument)
        end
      end

      candidates.compact.sort_by { |c| -c[:score] }.first(50)
    end

    private

    def passes_filters?(instrument)
      # Volume, price, liquidity filters
    end

    def analyze_instrument(instrument)
      # Load daily/weekly candles
      # Run indicators
      # Calculate score
    end
  end
end
```

### 3. AI Ranker Service

**`app/services/screeners/ai_ranker.rb`:**

```ruby
# frozen_string_literal: true

module Screeners
  class AIRanker < ApplicationService
    def self.call(candidates)
      new.call(candidates)
    end

    def call(candidates)
      # Use OpenAI to rank candidates
      # Return top N with confidence scores
    end
  end
end
```

### 4. Strategy Engine

**`app/services/strategies/swing/engine.rb`:**

```ruby
# frozen_string_literal: true

module Strategies
  module Swing
    class Engine < ApplicationService
      def self.call(instrument)
        new.call(instrument)
      end

      def call(instrument)
        # Load daily + weekly candles from DB
        # Fetch intraday on-demand (no storage)
        # Run indicators
        # Evaluate entry/exit signals
        # Return signal with confidence
      end
    end
  end
end
```

---

## Job Pipeline

### Daily Workflow (7:30 AM IST)

**1. Daily Candle Update:**

```ruby
# app/jobs/candles/daily_ingestor_job.rb
class Candles::DailyIngestorJob < ApplicationJob
  queue_as :default

  def perform
    Candles::DailyIngestor.call
  end
end
```

**2. Weekly Candle Update:**

```ruby
# app/jobs/candles/weekly_ingestor_job.rb
class Candles::WeeklyIngestorJob < ApplicationJob
  queue_as :default

  def perform
    Candles::WeeklyIngestor.call
  end
end
```

**3. Run Screener:**

```ruby
# app/jobs/screeners/swing_screener_job.rb
class Screeners::SwingScreenerJob < ApplicationJob
  queue_as :default

  def perform
    candidates = Screeners::SwingScreener.call
    Screeners::AIRankerJob.perform_later(candidates)
  end
end
```

**4. AI Ranking:**

```ruby
# app/jobs/screeners/ai_ranker_job.rb
class Screeners::AIRankerJob < ApplicationJob
  queue_as :default

  def perform(candidates)
    ranked = Screeners::AIRanker.call(candidates)
    Strategies::Swing::NotifierJob.perform_later(ranked)
  end
end
```

### Intraday Monitoring (Every 30 minutes during market hours)

**5. Swing Entry Monitor:**

```ruby
# app/jobs/strategies/swing_entry_monitor_job.rb
class Strategies::SwingEntryMonitorJob < ApplicationJob
  queue_as :default

  def perform
    # Check for entry signals
    # Use DhanHQ marketQuote API (not WebSocket)
  end
end
```

**6. Swing Exit Monitor:**

```ruby
# app/jobs/strategies/swing_exit_monitor_job.rb
class Strategies::SwingExitMonitorJob < ApplicationJob
  queue_as :default

  def perform
    # Check for exit signals
    # Use DhanHQ marketQuote API
  end
end
```

### Scheduling

**Use `config/recurring.yml` (SolidQueue recurring jobs):**

```yaml
# config/recurring.yml
candles_daily:
  class: Candles::DailyIngestorJob
  schedule: "0 30 7 * * *"  # 7:30 AM IST daily

candles_weekly:
  class: Candles::WeeklyIngestorJob
  schedule: "0 30 7 * * 1"  # 7:30 AM Monday

swing_screener:
  class: Screeners::SwingScreenerJob
  schedule: "0 40 7 * * 1-5"  # 7:40 AM weekdays

swing_entry_monitor:
  class: Strategies::SwingEntryMonitorJob
  schedule: "0 */30 9-15 * * 1-5"  # Every 30 min, 9 AM - 3 PM weekdays

swing_exit_monitor:
  class: Strategies::SwingExitMonitorJob
  schedule: "0 */30 9-15 * * 1-5"  # Every 30 min, 9 AM - 3 PM weekdays
```

---

## Testing Strategy

### Test Structure

```
spec/
├── models/
│   ├── instrument_spec.rb
│   └── candle_series_spec.rb
├── services/
│   ├── candles/
│   ├── screeners/
│   └── strategies/
└── jobs/
```

### Key Test Requirements

1. **Unit Tests:**
   - All services must have unit tests
   - Use FactoryBot for test data
   - Mock DhanHQ API calls with VCR/WebMock

2. **Integration Tests:**
   - Test full screening pipeline
   - Test candle ingestion flow
   - Test job scheduling

3. **Test Configuration:**
   - Disable DhanHQ in test: `ENV['DHANHQ_ENABLED'] = 'false'`
   - Use VCR for API recording
   - Use DatabaseCleaner for test isolation

---

## Verification Checklist

### Pre-Migration

- [ ] Backup AlgoScalperAPI database
- [ ] Document current AlgoScalperAPI configuration
- [ ] List all environment variables in use

### Migration Execution

- [ ] Create new Rails monolith
- [ ] Install all required gems
- [ ] Copy core models and migrations
- [ ] Copy indicator system
- [ ] Copy DhanHQ provider
- [ ] Copy Telegram notifier
- [ ] Create new service structure
- [ ] Create new job structure
- [ ] Update configuration files
- [ ] Run migrations successfully

### Post-Migration

- [ ] Verify models load without errors
- [ ] Verify services can be instantiated
- [ ] Test DhanHQ connection
- [ ] Test Telegram notifications
- [ ] Verify SolidQueue is working
- [ ] Test candle ingestion
- [ ] Test screener pipeline
- [ ] Run full test suite
- [ ] Verify no scalper code references

### Production Readiness

- [ ] All tests passing
- [ ] RuboCop checks passing
- [ ] Brakeman security scan clean
- [ ] Environment variables documented
- [ ] Deployment configuration ready
- [ ] Monitoring/logging configured
- [ ] Error handling comprehensive
- [ ] Documentation complete

---

## Critical Rules for New Repo

### ❌ ABSOLUTELY FORBIDDEN

1. **No WebSocket feeds** - Use REST API only
2. **No scalper logic** - Zero references to scalping
3. **No tick-level systems** - Only candle-based analysis
4. **No exit managers** - Simple exit logic only
5. **No bracket orders** - Use simple market/limit orders
6. **No Redis dependencies** - Use DB only (SolidQueue, SolidCache)

### ✅ REQUIRED

1. **DB-backed jobs** - SolidQueue only
2. **Daily/Weekly DB storage** - Store candles in DB
3. **Intraday on-demand** - Fetch when needed, don't store
4. **AI ranking** - OpenAI integration for candidate ranking
5. **Clean architecture** - Domain-driven folder structure
6. **Comprehensive logging** - All operations logged
7. **Error handling** - Graceful degradation everywhere

---

## Next Steps

After completing this migration:

1. **Set up Data Import** - See `docs/SWING_MIGRATION_DATA_SETUP.md` for instruments import
2. **Implement Candle Ingestion Pipeline** - See detailed implementation guide
3. **Implement Screener Pipeline** - See detailed implementation guide
4. **Implement Strategy Engine** - See detailed implementation guide
5. **Set up Monitoring** - Health endpoints, logging, alerts
6. **Deploy to Production** - VPS deployment with SolidQueue workers

---

## Support & Questions

For detailed implementation of specific components, refer to:
- **Data Setup & Import**: `docs/SWING_MIGRATION_DATA_SETUP.md` - Instruments importer, settings, rake tasks
- **Clean Importer Guide**: `docs/SWING_CLEAN_IMPORTER_GUIDE.md` - NSE stocks-only importer, universe filtering, watchlist cleanup
- Candle Ingestion: `docs/CANDLE_INGESTION_IMPLEMENTATION.md` (to be created)
- Screener Pipeline: `docs/SCREENER_PIPELINE_IMPLEMENTATION.md` (to be created)
- Strategy Engine: `docs/STRATEGY_ENGINE_IMPLEMENTATION.md` (to be created)

---

**End of Migration Guide**

