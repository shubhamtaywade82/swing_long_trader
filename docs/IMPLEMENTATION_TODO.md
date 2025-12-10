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
- [ ] Create `.env` file with DhanHQ credentials
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
- [ ] Write integration tests for ingestors (use VCR/WebMock)
- [ ] Write unit tests for dedup and upsert logic

---

## 📈 PHASE 6 — Indicators & SMC Modules

### Indicator Integration
- [ ] Verify all indicators work with CandleSeries model
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
- [ ] Create `app/services/screeners/swing_screener.rb`
- [ ] Create `app/services/screeners/longterm_screener.rb`
- [ ] Create `app/services/screeners/ai_ranker.rb`
- [ ] Create `app/services/screeners/final_selector.rb`

### Screener Logic Implementation
- [ ] Implement universe filter (from master_universe.yml)
- [ ] Implement basic filters (price, volume, active status)
- [ ] Implement trend filters (EMA20 > EMA50, etc.)
- [ ] Implement Supertrend alignment check
- [ ] Implement SMC structure validation
- [ ] Implement volatility calculation (ATR)
- [ ] Implement scoring system (rule hits)
- [ ] Return top 50 candidates

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
- [ ] Write unit tests for screener logic with fixture candles
- [ ] Write integration test (screener + AI with mocked OpenAI)
- [ ] Test final selector logic

---

## 🎯 PHASE 8 — Strategy Engine & Signal Builder

### Services to Create
- [ ] Create `app/services/strategies/swing/engine.rb`
- [ ] Create `app/services/strategies/swing/signal_builder.rb`
- [ ] Create `app/services/strategies/swing/evaluator.rb`
- [ ] Create `app/services/strategies/long_term/evaluator.rb`

### Swing Engine Implementation
- [ ] Accept instrument + multi-timeframe candles
- [ ] Validate SMC structure
- [ ] Compute entry price (breakout/retest logic)
- [ ] Compute stop loss (structure-based, ATR-based)
- [ ] Compute take profit (risk-reward & ATR)
- [ ] Calculate position size (risk-based)
- [ ] Calculate confidence score
- [ ] Estimate holding days
- [ ] Return standard signal hash format

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
- [ ] Write unit tests for signal builder with known candle series
- [ ] Test entry/SL/TP calculations
- [ ] Test position sizing logic

---

## 🤖 PHASE 9 — OpenAI Integration

### Implementation
- [ ] Create `app/services/openai/client.rb` wrapper
- [ ] Create `app/services/strategies/swing/ai_evaluator.rb`
- [ ] Build compact JSON-friendly prompt
- [ ] Request JSON response format from model
- [ ] Implement safe JSON parsing with fallback
- [ ] Add response caching (DB or Redis, 24h TTL)
- [ ] Implement rate limiting (top 50/day)
- [ ] Add token usage tracking
- [ ] Add cost monitoring/alerting

### Tests
- [ ] Mock OpenAI responses with WebMock
- [ ] Test JSON parsing and fallback logic
- [ ] Test caching behavior

---

## 🔬 PHASE 10 — Backtesting Framework (Swing & Long-Term)

**Goal:** Build comprehensive backtesting system to validate strategies before live trading

### Core Backtesting Infrastructure
- [ ] Create `app/services/backtesting/engine.rb` (main backtesting orchestrator)
- [ ] Create `app/services/backtesting/portfolio.rb` (virtual portfolio manager)
- [ ] Create `app/services/backtesting/position.rb` (virtual position tracker)
- [ ] Create `app/services/backtesting/result_analyzer.rb` (performance metrics)
- [ ] Create `app/models/backtest_run.rb` (store backtest results)
- [ ] Create `db/migrate/YYYYMMDDHHMMSS_create_backtest_runs.rb` migration
- [ ] Create `db/migrate/YYYYMMDDHHMMSS_create_backtest_positions.rb` migration

### Backtest Data Management
- [ ] Create `app/services/backtesting/data_loader.rb` (load historical candles)
- [ ] Implement date range selection (from_date, to_date)
- [ ] Implement instrument filtering (universe or specific symbols)
- [ ] Add data validation (ensure sufficient candles for indicators)
- [ ] Handle missing data gracefully (skip or interpolate)

### Swing Trading Backtesting
- [ ] Create `app/services/backtesting/swing_backtester.rb`
- [ ] Implement walk-forward backtesting (avoid look-ahead bias)
- [ ] Implement entry signal detection (use historical candles only)
- [ ] Implement exit signal detection (SL, TP, trailing stop)
- [ ] Implement position sizing (risk-based, fixed, or percentage)
- [ ] Track entry/exit timestamps and prices
- [ ] Calculate P&L per trade
- [ ] Calculate holding period per trade
- [ ] Handle partial fills and slippage simulation (optional)

### Long-Term Trading Backtesting
- [ ] Create `app/services/backtesting/long_term_backtester.rb`
- [ ] Implement weekly/monthly rebalancing logic
- [ ] Implement position holding for minimum period (30+ days)
- [ ] Implement exit conditions (profit target, stop loss, time-based)
- [ ] Track portfolio composition over time
- [ ] Calculate portfolio-level metrics

### Performance Metrics & Analysis
- [ ] Calculate total return (%)
- [ ] Calculate annualized return
- [ ] Calculate maximum drawdown
- [ ] Calculate Sharpe ratio
- [ ] Calculate Sortino ratio
- [ ] Calculate win rate (%)
- [ ] Calculate average win/loss ratio
- [ ] Calculate profit factor
- [ ] Calculate number of trades
- [ ] Calculate average holding period
- [ ] Calculate best/worst trade
- [ ] Calculate consecutive wins/losses
- [ ] Generate equity curve data
- [ ] Generate monthly returns breakdown
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
- [ ] Create `lib/tasks/backtest.rake`
- [ ] Implement `rails backtest:swing[from_date,to_date]` task
- [ ] Implement `rails backtest:long_term[from_date,to_date]` task
- [ ] Implement `rails backtest:compare[strategy1,strategy2]` task
- [ ] Implement `rails backtest:report[run_id]` task
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
- [ ] Write unit tests for backtesting engine
- [ ] Write unit tests for portfolio manager
- [ ] Write unit tests for position tracker
- [ ] Write unit tests for result analyzer
- [ ] Write integration tests with sample historical data
- [ ] Test walk-forward logic (no look-ahead bias)
- [ ] Test performance metrics calculations
- [ ] Test edge cases (no trades, all losses, all wins)

### Documentation
- [ ] Document backtesting methodology
- [ ] Document performance metrics definitions
- [ ] Document how to run backtests
- [ ] Document how to interpret results
- [ ] Document limitations and assumptions

---

## 📱 PHASE 11 — Telegram Notifier & Alert Formatting

### Implementation
- [ ] Create `app/services/telegram/notifier.rb` (if not exists)
- [ ] Create message templates/builders
- [ ] Implement daily candidate list message
- [ ] Implement swing signal alert message
- [ ] Implement exit alert message
- [ ] Implement P&L/portfolio snapshot message
- [ ] Implement exception/error alert message
- [ ] Format messages with emojis and structure
- [ ] Test message rendering

### Alert Types
- [ ] Daily candidate list (top 10)
- [ ] Signal alert (entry/SL/TP/RR details)
- [ ] Exit alert (exit condition triggered)
- [ ] Weekly P&L snapshot (optional)
- [ ] Job failure alerts
- [ ] API error alerts

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
- [ ] Create `app/jobs/candles/daily_ingestor_job.rb`
- [ ] Create `app/jobs/candles/weekly_ingestor_job.rb`
- [ ] Create `app/jobs/candles/intraday_fetcher_job.rb`
- [ ] Create `app/jobs/screeners/swing_screener_job.rb`
- [ ] Create `app/jobs/screeners/ai_ranker_job.rb`
- [ ] Create `app/jobs/strategies/swing_analysis_job.rb`
- [ ] Create `app/jobs/strategies/swing_entry_monitor_job.rb`
- [ ] Create `app/jobs/strategies/swing_exit_monitor_job.rb`
- [ ] Create `app/jobs/notifier_job.rb`
- [ ] Create `app/jobs/monitor_job.rb` (health checks)
- [ ] Create `app/jobs/executor_job.rb` (optional, order placement)

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
- [ ] Add job failure hooks (alert to Telegram)
- [ ] Monitor job queue length
- [ ] Configure retry strategies
- [ ] Add job duration tracking

### Tests
- [ ] Test job enqueueing
- [ ] Test job execution
- [ ] Test job retry logic
- [ ] Test job failure handling

---

## 🧪 PHASE 14 — Tests, CI/CD & QA

### Test Coverage
- [ ] Write unit tests for all services
- [ ] Write unit tests for all models
- [ ] Write integration tests with mocked Dhan responses
- [ ] Write integration tests with mocked OpenAI responses
- [ ] Write contract tests for Telegram messages
- [ ] Write smoke tests for rake tasks
- [ ] Achieve >80% code coverage

### CI/CD Setup
- [ ] Create `.github/workflows/ci.yml`
- [ ] Configure `bundle install` in CI
- [ ] Configure `rails db:create db:migrate RAILS_ENV=test`
- [ ] Configure `rspec` test run
- [ ] Configure RuboCop checks
- [ ] Configure Brakeman security scan
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
- [ ] Configure structured logging (lograge optional)
- [ ] Log job start/finish events
- [ ] Log alert send events
- [ ] Log order request/response events
- [ ] Log API call events (Dhan, OpenAI)

### Metrics
- [ ] Track Dhan API call counts (per day)
- [ ] Track OpenAI API call counts (per day)
- [ ] Track candidate counts
- [ ] Track signal counts
- [ ] Track P&L (if executing)
- [ ] Track job durations
- [ ] Track failed job counts

### Alerts
- [ ] Configure Telegram alerts for job failures
- [ ] Configure alerts for API rate limits (429 errors)
- [ ] Configure alerts for order failures
- [ ] Configure alerts for high error rates
- [ ] Test all alert types

---

## 📚 PHASE 16 — Documentation & Runbook

### Documentation
- [ ] Create/update `README.md` with local setup
- [ ] Create `docs/architecture.md` with diagrams
- [ ] Create `docs/runbook.md` with operational procedures
- [ ] Document how to stop auto-execution
- [ ] Document how to rebuild universe YAML
- [ ] Document how to run importers manually
- [ ] Document how to add instruments
- [ ] Document how to debug SolidQueue jobs
- [ ] Document environment variables
- [ ] Document API endpoints (if any)

---

## 🔒 PHASE 17 — Hardening & Go-Live Checklist

### Pre-Production Checks
- [ ] Enable dry-run mode (all orders to logs only)
- [ ] Run comprehensive backtest simulation (3+ months)
- [ ] Validate backtest results match expected performance
- [ ] Compare backtest results across different market conditions
- [ ] Implement manual accept for first 30 live trades
- [ ] Test idempotency thoroughly
- [ ] Test exposure limits thoroughly
- [ ] Confirm TLS for all API endpoints
- [ ] Store secrets in vault/ENV (not in code)
- [ ] Run load test of daily ingestion
- [ ] Run load test of screener on sample hardware
- [ ] Verify error handling for all failure modes
- [ ] Test circuit breakers
- [ ] Test rate limiting
- [ ] Test caching behavior

### Security
- [ ] Audit all API key storage
- [ ] Verify no secrets in logs
- [ ] Test SQL injection prevention
- [ ] Test XSS prevention (if web UI)
- [ ] Review all external API calls for security

### Production Readiness
- [ ] All tests passing
- [ ] All documentation complete
- [ ] Monitoring and alerts configured
- [ ] Runbook tested
- [ ] Team trained on operations
- [ ] Rollback plan documented
- [ ] Backup strategy in place

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

