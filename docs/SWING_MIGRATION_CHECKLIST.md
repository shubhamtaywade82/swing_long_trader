# ✅ SwingLongAlgoTrader Migration Checklist

**Quick reference checklist for creating the new Swing + Long-Term Trading repo**

---

## 📋 Pre-Migration Setup

- [ ] Backup AlgoScalperAPI database
- [ ] Document current environment variables
- [ ] List all active configuration in `config/algo.yml`
- [ ] Note any custom modifications to core services

---

## 🚀 Step 1: Create New Repo

- [ ] `rails new swing_long_trader --api -d postgresql`
- [ ] `cd swing_long_trader`
- [ ] `bundle install`
- [ ] `rails db:create`

---

## 📦 Step 2: Install Gems

- [ ] Add `solid_queue`, `solid_cache`, `solid_cable` to Gemfile
- [ ] Add `DhanHQ` gem (git source)
- [ ] Add `telegram-bot-ruby`
- [ ] Add `ruby-technical-analysis` and `technical-analysis`
- [ ] Add `activerecord-import`
- [ ] Run `bundle install`
- [ ] Run `rails g solid_queue:install`
- [ ] Run `rails db:migrate`

---

## 📁 Step 3: Copy Core Foundation

### Models
- [ ] Copy `app/models/instrument.rb`
- [ ] Copy `app/models/candle_series.rb`
- [ ] Copy `app/models/candle.rb`
- [ ] Copy `app/models/concerns/candle_extension.rb`
- [ ] Copy `app/models/concerns/instrument_helpers.rb`
- [ ] Copy `app/models/setting.rb` (NEW - for importer statistics)
- [ ] Copy `app/models/instrument_type_mapping.rb` (NEW - for importer)
- [ ] Copy `app/models/derivative.rb` (OPTIONAL - only if trading options)

### Indicators
- [ ] Copy entire `app/services/indicators/` directory
  - [ ] `base_indicator.rb`
  - [ ] `calculator.rb`
  - [ ] `indicator_factory.rb`
  - [ ] `threshold_config.rb`
  - [ ] `supertrend_indicator.rb`
  - [ ] `supertrend.rb`
  - [ ] `adx_indicator.rb`
  - [ ] `rsi_indicator.rb`
  - [ ] `macd_indicator.rb`
  - [ ] `trend_duration_indicator.rb`

### Providers
- [ ] Copy `lib/providers/dhanhq_provider.rb`
- [ ] Copy `app/services/concerns/dhanhq_error_handler.rb`

### Notifications
- [ ] Copy `lib/telegram_notifier.rb` or `lib/notifications/telegram_notifier.rb`
- [ ] Copy `config/initializers/telegram_notifier.rb`

### Base Services
- [ ] Copy `app/services/application_service.rb`

### Data Import & Setup
- [ ] Copy `app/services/instruments_importer.rb` (CRITICAL)
- [ ] Copy `lib/tasks/instruments.rake` (CRITICAL)
- [ ] Copy `db/seeds.rb` (modify heavily)

### Configuration
- [ ] Copy `config/initializers/algo_config.rb`
- [ ] Copy `config/initializers/dhanhq_config.rb`
- [ ] Create new `config/algo.yml` (swing-focused, not scalper)

---

## 🗄️ Step 4: Database Migrations

- [ ] Create `create_instruments` migration
  - [ ] Add all required columns
  - [ ] Add indexes: `instrument_code`, `security_id` (unique), composite `[exchange, segment, security_id]`
- [ ] Create `create_candle_series` migration
  - [ ] Add `instrument_id`, `timeframe`, `timestamp`, OHLCV columns
  - [ ] Add composite unique index: `[instrument_id, timeframe, timestamp]`
  - [ ] Add indexes: `[instrument_id, timeframe]`, `timestamp`
- [ ] Create `create_settings` migration
  - [ ] Add `key` (string, unique), `value` (text)
  - [ ] Add unique index on `key`
- [ ] Run `rails db:migrate`
- [ ] Verify schema: `rails db:schema:dump`

---

## 🏗️ Step 5: Create New Service Structure

### Candle Services
- [ ] Create `app/services/candles/daily_ingestor.rb`
- [ ] Create `app/services/candles/weekly_ingestor.rb`
- [ ] Create `app/services/candles/intraday_fetcher.rb`

### Screener Services
- [ ] Create `app/services/screeners/swing_screener.rb`
- [ ] Create `app/services/screeners/ai_ranker.rb`
- [ ] Create `app/services/screeners/final_selector.rb`

### Strategy Services
- [ ] Create `app/services/strategies/swing/engine.rb`
- [ ] Create `app/services/strategies/swing/evaluator.rb`
- [ ] Create `app/services/strategies/swing/notifier.rb`
- [ ] Create `app/services/strategies/swing/executor.rb`
- [ ] Create `app/services/strategies/long_term/engine.rb`
- [ ] Create `app/services/strategies/long_term/evaluator.rb`

---

## 🔄 Step 6: Create Job Pipeline

### Candle Jobs
- [ ] Create `app/jobs/candles/daily_ingestor_job.rb`
- [ ] Create `app/jobs/candles/weekly_ingestor_job.rb`
- [ ] Create `app/jobs/candles/intraday_fetcher_job.rb`

### Screener Jobs
- [ ] Create `app/jobs/screeners/swing_screener_job.rb`
- [ ] Create `app/jobs/screeners/ai_ranker_job.rb`

### Strategy Jobs
- [ ] Create `app/jobs/strategies/swing_analysis_job.rb`
- [ ] Create `app/jobs/strategies/swing_entry_monitor_job.rb`
- [ ] Create `app/jobs/strategies/swing_exit_monitor_job.rb`

### Scheduling
- [ ] Create `config/recurring.yml` with all job schedules
- [ ] Configure SolidQueue recurring jobs

---

## 📊 Step 7: Data Import Setup

- [ ] Copy `app/services/instruments_importer.rb`
- [ ] Copy `lib/tasks/instruments.rake`
- [ ] Modify importer for stocks-only (if not trading options)
- [ ] Test import: `rails instruments:import`
- [ ] Verify import: `rails instruments:status`
- [ ] Check instruments count: `rails runner "puts Instrument.count"`

## ⚙️ Step 8: Configuration

### Application Config
- [ ] Update `config/application.rb`:
  - [ ] Set `config.active_job.queue_adapter = :solid_queue`
  - [ ] Set time zone: `config.time_zone = 'Asia/Kolkata'`
  - [ ] Configure CORS

### Algo Config
- [ ] Create `config/algo.yml` with swing trading config
  - [ ] Swing trading settings
  - [ ] Long-term trading settings
  - [ ] Candle ingestion settings
  - [ ] Indicator configurations
  - [ ] AI ranking settings
  - [ ] Notification settings

### Environment Variables
- [ ] Create `.env.example` with all required variables:
  - [ ] `DHANHQ_CLIENT_ID` or `CLIENT_ID`
  - [ ] `DHANHQ_ACCESS_TOKEN` or `ACCESS_TOKEN`
  - [ ] `TELEGRAM_BOT_TOKEN`
  - [ ] `TELEGRAM_CHAT_ID`
  - [ ] `RAILS_ENV`
  - [ ] `RAILS_LOG_LEVEL`

---

## ❌ Step 9: Remove Scalper Code

### Verify NOT Copied
- [ ] No `app/services/live/` directory
- [ ] No `app/services/entries/` directory
- [ ] No `app/services/orders/` directory (or only basic order placement)
- [ ] No `app/services/positions/` directory
- [ ] No `app/services/risk/` directory
- [ ] No `app/services/signal/` directory (scalper signals)
- [ ] No `app/services/trading/` directory
- [ ] No `app/models/position_tracker.rb`
- [ ] No WebSocket initializers
- [ ] No tick cache services
- [ ] No bracket order services
- [ ] No exit manager services

---

## ✅ Step 10: Verification

### Code Verification
- [ ] Run `rails console` - no errors
- [ ] Load models: `Instrument.first`, `CandleSeries.first`
- [ ] Load services: `Candles::DailyIngestor.call` (dry run)
- [ ] Test DhanHQ connection: `DhanhqProvider.new.client`
- [ ] Test Telegram: `TelegramNotifier.new.send_message("test")`

### Database Verification
- [ ] Verify `instruments` table exists with correct schema
- [ ] Verify `candle_series` table exists with correct schema
- [ ] Verify all indexes are created
- [ ] Test insert: Create test instrument and candle

### Job Verification
- [ ] Verify SolidQueue tables exist
- [ ] Test job enqueue: `Candles::DailyIngestorJob.perform_later`
- [ ] Check SolidQueue dashboard/console
- [ ] Verify recurring jobs are registered

### Configuration Verification
- [ ] `AlgoConfig.fetch('swing_trading.enabled')` returns value
- [ ] DhanHQ config loads correctly
- [ ] Telegram config loads correctly

---

## 🧪 Step 11: Testing Setup

### Test Configuration
- [ ] Set `ENV['DHANHQ_ENABLED'] = 'false'` in test environment
- [ ] Configure VCR for API recording
- [ ] Configure WebMock for HTTP stubbing
- [ ] Set up DatabaseCleaner

### Test Files
- [ ] Create `spec/models/instrument_spec.rb`
- [ ] Create `spec/models/candle_series_spec.rb`
- [ ] Create `spec/services/candles/daily_ingestor_spec.rb`
- [ ] Create `spec/services/screeners/swing_screener_spec.rb`
- [ ] Create `spec/jobs/candles/daily_ingestor_job_spec.rb`

### Run Tests
- [ ] `bundle exec rspec` - all tests pass
- [ ] `bundle exec rubocop` - no style violations
- [ ] `bundle exec brakeman` - no security issues

---

## 📝 Step 12: Documentation

- [ ] Create `README.md` with setup instructions
- [ ] Document environment variables
- [ ] Document job schedules
- [ ] Document API endpoints (if any)
- [ ] Create architecture diagram
- [ ] Document deployment process

---

## 🚀 Step 13: Production Readiness

### Code Quality
- [ ] All RuboCop checks pass
- [ ] All Brakeman security checks pass
- [ ] All tests pass
- [ ] Code coverage > 80% (if using SimpleCov)

### Configuration
- [ ] Production environment variables documented
- [ ] Secrets management configured (encrypted credentials or ENV)
- [ ] Logging configured (STDOUT for production)
- [ ] Error tracking configured (if using)

### Deployment
- [ ] Dockerfile created (if using Docker)
- [ ] Deployment scripts ready
- [ ] Database migration strategy defined
- [ ] Rollback plan documented

### Monitoring
- [ ] Health check endpoint created
- [ ] Logging structured and searchable
- [ ] Alerts configured (if using monitoring service)
- [ ] Performance monitoring setup

---

## 🎯 Critical Success Criteria

### Must Have
- ✅ Zero scalper code references
- ✅ All jobs use SolidQueue (DB-backed)
- ✅ Daily/Weekly candles stored in DB
- ✅ Intraday fetched on-demand (not stored)
- ✅ AI ranking functional
- ✅ Telegram notifications working
- ✅ All tests passing

### Should Have
- ✅ Comprehensive error handling
- ✅ Structured logging
- ✅ Health check endpoints
- ✅ Documentation complete
- ✅ Production deployment ready

---

## 📚 Reference Files

- **Full Migration Guide**: `docs/SWING_LONG_TRADER_MIGRATION_GUIDE.md`
- **Service Architecture**: See migration guide section
- **Job Pipeline**: See migration guide section
- **Configuration Examples**: See migration guide section

---

**Last Updated:** Based on AlgoScalperAPI codebase analysis

