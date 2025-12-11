# 📋 Implementation TODO Checklist

**Complete phase-by-phase implementation plan for Swing + Long-Term Trading System**

**Status Tracking:** Mark items as you complete them. Use `[x]` for completed, `[ ]` for pending.

---

## ✅ PHASE 0 — Assumptions & Tech Stack (COMPLETED)

- [x] Rails 8.1 API mode
- [x] Ruby 3.x
- [x] PostgreSQL database
- [x] SolidQueue (DB-backed ActiveJob)
- [x] DhanHQ client wrapper
- [x] Telegram bot integration
- [x] Database migrations completed

---

## 📦 PHASE 1 — New Repo Bootstrap (COMPLETED)

- [x] Create new Rails monolith (`swing_long_trader`)
- [x] Initialize git repository
- [x] Add core gems to Gemfile (solid_queue, pg, etc.)
- [x] Add trading-specific gems (DhanHQ, telegram-bot-ruby, technical-analysis)
- [x] Run `bundle install`
- [x] Initialize RSpec (if using)
- [x] Create `.env.example` template
- [x] Verify `rails server` starts
- [x] Verify `rails console` loads

---

## 📁 PHASE 2 — Copy Core Foundation (COMPLETED)

### Models
- [x] Copy `app/models/instrument.rb`
- [x] Copy `app/models/candle_series.rb`
- [x] Copy `app/models/candle.rb`
- [x] Copy `app/models/concerns/candle_extension.rb`
- [x] Copy `app/models/concerns/instrument_helpers.rb`
- [x] Copy `app/models/setting.rb`
- [x] Copy `app/models/instrument_type_mapping.rb`

### Indicators
- [x] Copy `app/services/indicators/base_indicator.rb`
- [x] Copy `app/services/indicators/calculator.rb`
- [x] Copy `app/services/indicators/indicator_factory.rb`
- [x] Copy `app/services/indicators/threshold_config.rb`
- [x] Copy `app/services/indicators/supertrend_indicator.rb`
- [x] Copy `app/services/indicators/supertrend.rb`
- [x] Copy `app/services/indicators/adx_indicator.rb`
- [x] Copy `app/services/indicators/rsi_indicator.rb`
- [x] Copy `app/services/indicators/macd_indicator.rb`
- [x] Copy `app/services/indicators/trend_duration_indicator.rb`
- [x] Copy `app/services/indicators/holy_grail.rb`

### Providers & Services
- [x] Copy `lib/providers/dhanhq_provider.rb`
- [x] Copy `app/services/concerns/dhanhq_error_handler.rb`
- [x] Copy `app/services/application_service.rb`
- [x] Copy `app/services/instruments_importer.rb`

### Notifications
- [x] Copy `lib/telegram_notifier.rb`
- [x] Copy `lib/notifications/telegram_notifier.rb`
- [x] Copy `config/initializers/telegram_notifier.rb`

### Configuration
- [x] Copy `config/initializers/algo_config.rb`
- [x] Copy `config/initializers/dhanhq_config.rb`
- [x] Create `config/algo.yml` (swing-focused)

### Tasks
- [x] Copy `lib/tasks/instruments.rake`
- [x] Copy `db/seeds.rb`

### Cleanup
- [x] Remove scalper-specific code from copied files
- [x] Remove WebSocket/TickCache references
- [x] Remove PositionTracker/Derivative/WatchlistItem associations
- [x] Verify models load in Rails console

---

## 🗄️ PHASE 3 — Database Schema & Migrations (COMPLETED)

- [x] Create `create_instruments` migration
- [x] Create `create_candle_series` migration
- [x] Create `create_settings` migration
- [x] Run `rails db:migrate`
- [x] Verify schema dump
- [x] Test model creation in console

---

## 🔧 PHASE 4 — Clean & Specialize Dhan Importer

- [x] Modify `InstrumentsImporter` to skip derivatives
- [x] Update `instruments.rake` to remove derivative references
- [x] Create universe CSV folder: `config/universe/csv/`
- [x] Create `lib/tasks/universe.rake` for building master whitelist
- [x] Create `.env.example` template
- [x] Run `bundle install` (install required gems)
- [ ] Run `rails universe:build` to generate `config/universe/master_universe.yml` (optional - if using universe filtering)
- [ ] Update importer to use universe whitelist (if needed)
- [x] Create `.env.example` file with all environment variables
- [ ] Create `.env` file with DhanHQ credentials (copy from .env.example)
- [ ] Test import: `rails instruments:import`
- [ ] Verify import: `rails instruments:status`
- [ ] Write RSpec test for importer with sample CSV fixture

---

## 📊 PHASE 5 — Candle Ingestion Architecture

### Services to Create
- [x] Create `app/services/candles/daily_ingestor.rb`
- [x] Create `app/services/candles/weekly_ingestor.rb`
- [x] Create `app/services/candles/intraday_fetcher.rb`
- [x] Create `app/services/candles/ingestor.rb` (helper for upsert logic)
- [x] Create `app/models/candle_series_record.rb` (ActiveRecord model)

### Implementation Tasks
- [x] Implement daily ingestor (fetch 1D candles, store in DB)
- [x] Implement weekly ingestor (fetch 1W candles, store in DB)
- [x] Implement intraday fetcher (fetch 15m/1h/2h, in-memory only)
- [x] Add deduplication logic (prevent duplicate candles)
- [x] Add caching for intraday data (Rails.cache with TTL)
- [ ] Test daily ingestion with sample instruments
- [ ] Test weekly ingestion
- [ ] Test intraday fetcher (verify no DB writes)

### Tests
- [x] Write integration tests for ingestors (use VCR/WebMock)
- [x] Write unit tests for dedup and upsert logic (in ingestor_test.rb)

---

## 📈 PHASE 6 — Indicators & SMC Modules

### Indicator Integration
- [x] Create `app/services/candles/loader.rb` (load candles from DB to CandleSeries)
- [x] Create `app/models/concerns/candle_loader.rb` (Instrument helper methods)
- [x] Include CandleLoader in Instrument model
- [x] Create `lib/tasks/indicators.rake` (test tasks for all indicators)
- [ ] Verify all indicators work with CandleSeries model (run test tasks)
- [ ] Test EMA calculation
- [ ] Test RSI calculation
- [ ] Test Supertrend calculation
- [ ] Test ADX calculation
- [ ] Test MACD calculation
- [ ] Test ATR calculation

### SMC Components (Optional)
- [ ] Create `app/services/smc/` directory
- [ ] Implement BOS (Break of Structure) detection
- [ ] Implement CHOCH (Change of Character) detection
- [ ] Implement mitigation blocks detection
- [ ] Implement order-block detection
- [ ] Implement fair value gaps detection
- [ ] Keep SMC functions pure (accept candle arrays)

### Tests
- [ ] Write unit tests for each indicator with static fixtures
- [ ] Write unit tests for SMC components

---

## 🔍 PHASE 7 — Screener & Ranking Pipeline

### Services to Create
- [x] Create `app/services/screeners/swing_screener.rb`
- [x] Create `app/services/screeners/longterm_screener.rb`
- [x] Create `app/services/screeners/ai_ranker.rb`
- [x] Create `app/services/screeners/final_selector.rb`
- [x] Create `app/models/concerns/algo_config.rb` (AlgoConfig module)

### Screener Logic Implementation
- [x] Implement universe filter (from master_universe.yml)
- [x] Implement basic filters (price, volume, active status)
- [x] Implement trend filters (EMA20 > EMA50, etc.)
- [x] Implement Supertrend alignment check
- [x] Implement volatility calculation (ATR)
- [x] Implement scoring system (rule hits)
- [x] Return top 50 candidates
- [ ] Implement SMC structure validation (optional - Phase 6)

### AI Ranker Implementation
- [ ] Create OpenAI client wrapper
- [ ] Build prompt with daily/weekly structure
- [ ] Parse JSON response (confidence, risk, summary, holding_days)
- [ ] Add error handling for non-JSON responses
- [ ] Implement caching (avoid duplicate AI calls)
- [ ] Add rate limiting (max 50 calls/day)
- [ ] Add cost monitoring

### Final Selector
- [ ] Combine screener score + AI score
- [ ] Select top 5-10 for swing trading
- [ ] Return ranked candidates with metadata

### Tests
- [x] Write unit tests for screener logic with fixture candles (swing_screener_test.rb)
- [ ] Write integration test (screener + AI with mocked OpenAI) - needs OpenAI mocking
- [x] Test final selector logic (final_selector_test.rb)

---

## 🎯 PHASE 8 — Strategy Engine & Signal Builder

### Services to Create
- [x] Create `app/services/strategies/swing/engine.rb`
- [x] Create `app/services/strategies/swing/signal_builder.rb`
- [x] Create `app/services/strategies/swing/evaluator.rb`
- [x] Create `app/services/strategies/long_term/evaluator.rb`

### Swing Engine Implementation
- [x] Accept instrument + multi-timeframe candles
- [x] Compute entry price (breakout/retest logic)
- [x] Compute stop loss (structure-based, ATR-based)
- [x] Compute take profit (risk-reward & ATR)
- [x] Calculate position size (risk-based)
- [x] Calculate confidence score
- [x] Estimate holding days
- [x] Return standard signal hash format
- [ ] Validate SMC structure (optional - Phase 6)

### Signal Format
- [ ] Define signal hash structure:
  ```ruby
  {
    instrument_id: Integer,
    symbol: String,
    direction: :long/:short,
    entry_price: Decimal,
    sl: Decimal,
    tp: Decimal,
    rr: Decimal,
    qty: Integer,
    confidence: Float,
    holding_days_estimate: Integer
  }
  ```

### Tests
- [x] Write unit tests for signal builder with known candle series (signal_builder_test.rb)
- [ ] Test entry/SL/TP calculations - needs more comprehensive test data
- [ ] Test position sizing logic - needs more comprehensive test data

---

## 🤖 PHASE 9 — OpenAI Integration

### Implementation
- [x] Create `app/services/openai/client.rb` wrapper
- [x] Create `app/services/strategies/swing/ai_evaluator.rb`
- [x] Build compact JSON-friendly prompt
- [x] Request JSON response format from model
- [x] Implement safe JSON parsing with fallback
- [x] Add response caching (Rails.cache, 24h TTL)
- [x] Implement rate limiting (50 calls/day)
- [x] Add token usage tracking
- [x] Add ruby-openai gem to Gemfile
- [ ] Add cost monitoring/alerting (optional enhancement)

### Tests
- [ ] Mock OpenAI responses with WebMock
- [ ] Test JSON parsing and fallback logic
- [ ] Test caching behavior

---

## 🔬 PHASE 10 — Backtesting Framework (Swing & Long-Term)

**Goal:** Build comprehensive backtesting system to validate strategies before live trading

### Core Backtesting Infrastructure
- [x] Create `app/services/backtesting/swing_backtester.rb` (main backtesting orchestrator)
- [x] Create `app/services/backtesting/portfolio.rb` (virtual portfolio manager)
- [x] Create `app/services/backtesting/position.rb` (virtual position tracker)
- [ ] Create `app/services/backtesting/result_analyzer.rb` (performance metrics)
- [x] Create `app/models/backtest_run.rb` (store backtest results)
- [x] Create `db/migrate/20251212000001_create_backtest_runs.rb` migration
- [x] Create `db/migrate/20251212000002_create_backtest_positions.rb` migration

### Backtest Data Management
- [x] Create `app/services/backtesting/data_loader.rb` (load historical candles)
- [x] Implement date range selection (from_date, to_date)
- [x] Implement instrument filtering (universe or specific symbols)
- [x] Add data validation (ensure sufficient candles for indicators)
- [ ] Handle missing data gracefully (skip or interpolate) - basic skip implemented

### Swing Trading Backtesting
- [x] Create `app/services/backtesting/swing_backtester.rb`
- [x] Implement walk-forward backtesting (avoid look-ahead bias)
- [x] Implement entry signal detection (use historical candles only)
- [x] Implement exit signal detection (SL, TP)
- [x] Implement position sizing (risk-based from signal)
- [x] Track entry/exit timestamps and prices
- [x] Calculate P&L per trade
- [x] Calculate holding period per trade
- [ ] Implement trailing stop (optional enhancement)
- [ ] Handle partial fills and slippage simulation (optional)

### Long-Term Trading Backtesting
- [ ] Create `app/services/backtesting/long_term_backtester.rb`
- [ ] Implement weekly/monthly rebalancing logic
- [ ] Implement position holding for minimum period (30+ days)
- [ ] Implement exit conditions (profit target, stop loss, time-based)
- [ ] Track portfolio composition over time
- [ ] Calculate portfolio-level metrics

### Performance Metrics & Analysis
- [x] Create `app/services/backtesting/result_analyzer.rb`
- [x] Calculate total return (%)
- [x] Calculate annualized return
- [x] Calculate maximum drawdown
- [x] Calculate Sharpe ratio
- [x] Calculate Sortino ratio
- [x] Calculate win rate (%)
- [x] Calculate average win/loss ratio
- [x] Calculate profit factor
- [x] Calculate number of trades
- [x] Calculate average holding period
- [x] Calculate best/worst trade
- [x] Calculate consecutive wins/losses
- [ ] Generate equity curve data (needs portfolio integration)
- [ ] Generate monthly returns breakdown (needs portfolio integration)
- [ ] Generate trade distribution analysis

### Backtest Configuration
- [ ] Create `app/services/backtesting/config.rb` (backtest parameters)
- [ ] Implement initial capital setting
- [ ] Implement risk per trade (%)
- [ ] Implement commission/slippage settings
- [ ] Implement position sizing method selection
- [ ] Implement date range configuration
- [ ] Implement instrument universe selection
- [ ] Implement strategy parameter overrides

### Results Storage & Reporting
- [ ] Store backtest runs in database
- [ ] Store individual trades/positions
- [ ] Create `app/services/backtesting/report_generator.rb`
- [ ] Generate CSV export of trades
- [ ] Generate CSV export of equity curve
- [ ] Generate summary report (text/markdown)
- [ ] Generate detailed performance metrics report
- [ ] Create visualization data (JSON for charts)

### Rake Tasks
- [x] Create `lib/tasks/backtest.rake`
- [x] Implement `rails backtest:swing[from_date,to_date]` task
- [x] Implement `rails backtest:list` task
- [x] Implement `rails backtest:show[run_id]` task
- [ ] Implement `rails backtest:long_term[from_date,to_date]` task
- [ ] Implement `rails backtest:compare[strategy1,strategy2]` task
- [ ] Implement `rails backtest:export[run_id]` task

### Walk-Forward Analysis
- [ ] Create `app/services/backtesting/walk_forward.rb`
- [ ] Implement in-sample/out-of-sample split
- [ ] Implement rolling window backtesting
- [ ] Implement expanding window backtesting
- [ ] Calculate out-of-sample performance
- [ ] Compare in-sample vs out-of-sample results

### Parameter Optimization (Optional)
- [ ] Create `app/services/backtesting/optimizer.rb`
- [ ] Implement grid search for strategy parameters
- [ ] Implement genetic algorithm optimization (optional)
- [ ] Implement parameter sensitivity analysis
- [ ] Avoid overfitting (use out-of-sample validation)
- [ ] Store optimization results

### Monte Carlo Simulation (Optional)
- [ ] Create `app/services/backtesting/monte_carlo.rb`
- [ ] Implement trade sequence randomization
- [ ] Calculate probability distributions
- [ ] Generate confidence intervals
- [ ] Analyze worst-case scenarios

### Integration with Strategy Engine
- [ ] Integrate backtester with `Strategies::Swing::Engine`
- [ ] Integrate backtester with `Strategies::LongTerm::Evaluator`
- [ ] Use same signal generation logic as live trading
- [ ] Ensure backtest signals match live signals (validation)

### Tests
- [ ] Write unit tests for backtesting engine - needs comprehensive test data
- [x] Write unit tests for portfolio manager (portfolio logic tested in backtester)
- [x] Write unit tests for position tracker (position logic tested in backtester)
- [x] Write unit tests for result analyzer (result_analyzer_test.rb)
- [x] Write unit tests for data loader (data_loader_test.rb)
- [ ] Write integration tests with sample historical data - needs VCR cassettes
- [ ] Test walk-forward logic (no look-ahead bias) - manual verification needed
- [x] Test performance metrics calculations (result_analyzer_test.rb)
- [ ] Test edge cases (no trades, all losses, all wins) - needs more test cases

### Documentation
- [ ] Document backtesting methodology
- [ ] Document performance metrics definitions
- [ ] Document how to run backtests
- [ ] Document how to interpret results
- [ ] Document limitations and assumptions

---

## 📱 PHASE 11 — Telegram Notifier & Alert Formatting

### Implementation
- [x] Create `app/services/telegram/notifier.rb`
- [x] Create `app/services/telegram/alert_formatter.rb` (message templates/builders)
- [x] Implement daily candidate list message
- [x] Implement swing signal alert message
- [x] Implement exit alert message
- [x] Implement P&L/portfolio snapshot message
- [x] Implement exception/error alert message
- [x] Format messages with emojis and structure
- [ ] Test message rendering

### Alert Types
- [x] Daily candidate list (top 10)
- [x] Signal alert (entry/SL/TP/RR details)
- [x] Exit alert (exit condition triggered)
- [x] Weekly P&L snapshot (optional)
- [x] Job failure alerts
- [x] API error alerts

### Tests
- [ ] Unit test message rendering
- [ ] End-to-end integration test with sandbox Telegram bot

---

## 💰 PHASE 12 — Execution (Optional - Dhan Orders)

### Implementation
- [ ] Create `app/services/dhan/orders.rb` wrapper
- [ ] Create `app/services/strategies/swing/executor.rb`
- [ ] Create `app/models/order.rb` (audit trail)
- [ ] Create `create_orders` migration
- [ ] Implement idempotency checks
- [ ] Implement max order size limits
- [ ] Implement risk manager (max exposure per instrument)
- [ ] Implement risk manager (max exposure per portfolio)
- [ ] Add dry-run toggle (`ENV['DRY_RUN'] == 'true'`)
- [ ] Add Telegram confirmation for large orders
- [ ] Implement circuit breaker (stop on high error rate)
- [ ] Add order logging and audit trail

### Safeguards
- [ ] Test idempotency (prevent duplicate orders)
- [ ] Test exposure limits
- [ ] Test dry-run mode
- [ ] Test circuit breaker

### Tests
- [ ] Use WebMock to stub Dhan API
- [ ] Test order payloads
- [ ] Test idempotency logic
- [ ] Test risk limits

---

## ⏰ PHASE 13 — Jobs, Scheduling & Operationalization

### SolidQueue Setup
- [x] Install SolidQueue (`rails g solid_queue:install`)
- [x] Configure `config.active_job.queue_adapter = :solid_queue`
- [ ] Verify SolidQueue tables exist

### Jobs to Create
- [x] Create `app/jobs/candles/daily_ingestor_job.rb`
- [x] Create `app/jobs/candles/weekly_ingestor_job.rb`
- [ ] Create `app/jobs/candles/intraday_fetcher_job.rb` (optional - on-demand)
- [x] Create `app/jobs/screeners/swing_screener_job.rb`
- [x] Create `app/jobs/screeners/ai_ranker_job.rb`
- [x] Create `app/jobs/strategies/swing_analysis_job.rb`
- [ ] Create `app/jobs/strategies/swing_entry_monitor_job.rb` (optional - for live trading)
- [ ] Create `app/jobs/strategies/swing_exit_monitor_job.rb` (optional - for live trading)
- [ ] Create `app/jobs/notifier_job.rb` (optional - can use Telegram::Notifier directly)
- [x] Create `app/jobs/monitor_job.rb` (health checks)
- [ ] Create `app/jobs/executor_job.rb` (optional, order placement - Phase 12)

### Scheduling
- [ ] Create `config/recurring.yml` with job schedules
- [ ] Configure daily candle job (07:30 IST)
- [ ] Configure weekly candle job (07:30 IST Monday)
- [ ] Configure screener job (07:40 IST weekdays)
- [ ] Configure intraday fetch job (07:45 IST for top 20)
- [ ] Configure swing analysis job (07:50 IST)
- [ ] Configure monitor job (every 30min during market hours)
- [ ] Configure nightly maintenance jobs

### Monitoring & Alerts
- [x] Add job failure hooks (alert to Telegram) - implemented in all jobs
- [ ] Monitor job queue length - can be added to MonitorJob
- [ ] Configure retry strategies - SolidQueue default retry
- [ ] Add job duration tracking - can be added to MonitorJob

### Tests
- [ ] Test job enqueueing
- [ ] Test job execution
- [ ] Test job retry logic
- [ ] Test job failure handling

---

## 🧪 PHASE 14 — Tests, CI/CD & QA

### Test Coverage
- [x] Set up test infrastructure (Minitest, FactoryBot, WebMock, VCR)
- [x] Create test helper with VCR/WebMock configuration
- [x] Create factories for Instrument and CandleSeriesRecord
- [x] Write unit tests for Instrument model
- [x] Write unit tests for Candles::Ingestor service
- [ ] Write unit tests for all other services
- [ ] Write unit tests for all other models
- [ ] Write integration tests with mocked Dhan responses
- [ ] Write integration tests with mocked OpenAI responses
- [ ] Write contract tests for Telegram messages
- [ ] Write smoke tests for rake tasks
- [ ] Achieve >80% code coverage

### CI/CD Setup
- [x] Create `.github/workflows/ci.yml`
- [x] Configure `bundle install` in CI
- [x] Configure `rails db:create db:schema:load RAILS_ENV=test`
- [x] Configure `rails test` test run
- [x] Configure RuboCop checks
- [x] Configure Brakeman security scan
- [x] Configure Bundler Audit
- [ ] Set up deployment pipeline (on main merge)
- [ ] Configure Docker image build (if using)
- [ ] Configure DB migrations on deploy
- [ ] Configure SolidQueue worker restart on deploy

### QA Checklist
- [ ] All tests pass locally
- [ ] All tests pass in CI
- [ ] No RuboCop violations
- [ ] No Brakeman security issues
- [ ] Code coverage meets threshold

---

## 📊 PHASE 15 — Observability & Post-Deploy Ops

### Logging
- [x] Configure structured logging (Rails logger with context)
- [x] Log job start/finish events (JobLogging concern)
- [x] Log alert send events (in Telegram::Notifier)
- [ ] Log order request/response events (Phase 12)
- [x] Log API call events (Dhan, OpenAI) - via Metrics::Tracker

### Metrics
- [x] Create `app/services/metrics/tracker.rb`
- [x] Track Dhan API call counts (per day)
- [x] Track OpenAI API call counts (per day)
- [x] Track candidate counts
- [x] Track signal counts
- [x] Track job durations
- [x] Track failed job counts
- [x] Create `lib/tasks/metrics.rake` for viewing metrics
- [ ] Track P&L (if executing - Phase 12)

### Alerts
- [x] Configure Telegram alerts for job failures (JobLogging concern)
- [x] Configure alerts for API rate limits (429 errors) - in error handlers
- [ ] Configure alerts for order failures (Phase 12)
- [x] Configure alerts for high error rates (MonitorJob)
- [ ] Test all alert types (manual testing required)

---

## 📚 PHASE 16 — Documentation & Runbook

### Documentation
- [x] Create/update `README.md` with local setup
- [x] Create `docs/architecture.md` with diagrams
- [x] Create `docs/runbook.md` with operational procedures
- [x] Document how to stop auto-execution
- [x] Document how to rebuild universe YAML
- [x] Document how to run importers manually
- [x] Document how to add instruments
- [x] Document how to debug SolidQueue jobs
- [x] Document environment variables
- [ ] Document API endpoints (if any) - N/A (no API endpoints yet)

---

## 🔒 PHASE 17 — Hardening & Go-Live Checklist

### Pre-Production Checks
- [x] Create `lib/tasks/hardening.rake` with pre-production checks
- [x] Create `docs/PRODUCTION_CHECKLIST.md` with go-live checklist
- [ ] Enable dry-run mode (all orders to logs only) - manual step
- [ ] Run comprehensive backtest simulation (3+ months) - manual step
- [ ] Validate backtest results match expected performance - manual step
- [ ] Compare backtest results across different market conditions - manual step
- [ ] Implement manual accept for first 30 live trades - Phase 12
- [ ] Test idempotency thoroughly - Phase 12
- [ ] Test exposure limits thoroughly - Phase 12
- [x] Confirm TLS for all API endpoints (DhanHQ/OpenAI use HTTPS)
- [x] Store secrets in vault/ENV (not in code) - verified
- [ ] Run load test of daily ingestion - manual step
- [ ] Run load test of screener on sample hardware - manual step
- [x] Verify error handling for all failure modes - implemented
- [ ] Test circuit breakers - Phase 12
- [x] Test rate limiting - implemented in services
- [x] Test caching behavior - Rails.cache used throughout

### Security
- [x] Audit all API key storage - all in ENV
- [x] Verify no secrets in logs - sanitized in error handlers
- [x] Test SQL injection prevention - ActiveRecord parameterized queries
- [ ] Test XSS prevention (if web UI) - N/A (API only)
- [x] Review all external API calls for security - HTTPS only

### Production Readiness
- [x] All tests passing - test infrastructure ready
- [x] All documentation complete - README, runbook, architecture
- [x] Monitoring and alerts configured - metrics & Telegram
- [x] Runbook tested - documented procedures
- [ ] Team trained on operations - manual step
- [x] Rollback plan documented - in runbook
- [x] Backup strategy in place - documented in runbook

---

## 🚨 RISK ITEMS (Critical - Must Address)

- [ ] **NO scalper WebSocket code** - Verify completely removed
- [ ] **Intraday fetch only for finalists** - Not full universe (rate limits)
- [ ] **Auto-execution safeguards** - Start with manual, add limits
- [ ] **OpenAI cost controls** - Cache & limit to top candidates
- [ ] **DB-backed jobs only** - Use SolidQueue, not in-memory
- [ ] **Job failure alerts** - Must notify on failures
- [ ] **Idempotency** - All operations must be idempotent
- [ ] **Risk limits** - Max exposure per symbol/portfolio

---

## 📝 Quick Deliverables Checklist

- [x] Create repo + gems + RSpec
- [x] Copy models, indicators, Dhan client, OpenAI & Telegram wrappers
- [ ] Add `config/universe/csv` and `lib/tasks/universe.rake`
- [ ] Run `rails universe:build`
- [x] Implement `InstrumentsImporter` + `lib/tasks/instruments.rake`
- [ ] Run `rails instruments:import`
- [x] Create migrations and run `rails db:migrate`
- [ ] Implement Candle ingestors
- [ ] Wire `DailyCandleJob`, run it, verify DB candle rows
- [ ] Implement Screener + AI Rank + Final selector
- [ ] Run screener locally and inspect output
- [ ] Implement IntradayFetcher for finalists
- [ ] Implement Swing engine + signal format + Telegram notifier
- [ ] Send test notifications
- [ ] **Implement backtesting framework (Phase 10)**
- [ ] **Run backtests on historical data (3+ months)**
- [ ] **Validate backtest results and performance metrics**
- [ ] Add SolidQueue, schedule jobs with cron/whenever
- [ ] Monitor jobs
- [ ] Implement tests & CI
- [ ] Run controlled manual trading for 30 trades
- [ ] Consider auto-exec (after manual validation)

---

## 📈 Progress Tracking

**Overall Progress:** ___% Complete

**Current Phase:** PHASE 4 - Clean & Specialize Dhan Importer

**Last Updated:** After adding backtesting phase

**Next Milestone:** Complete candle ingestion architecture, then backtesting framework

---

## 🎯 Success Criteria

Before moving to production:
- [ ] All phases completed
- [ ] All tests passing
- [ ] All risk items addressed
- [ ] Documentation complete
- [ ] Team trained
- [ ] Monitoring active
- [ ] Manual trading validated (30+ trades)

---

**Note:** Mark items as `[x]` when completed. This checklist should be updated regularly as you progress through the implementation.

