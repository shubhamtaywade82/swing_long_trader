# System Overview

**Complete guide to understanding and operating the Swing + Long-Term Trading System**

---

## Table of Contents

1. [System Architecture](#system-architecture)
2. [Core Components](#core-components)
3. [Data Flow](#data-flow)
4. [Key Workflows](#key-workflows)
5. [Configuration](#configuration)
6. [Quick Reference](#quick-reference)
7. [Common Tasks](#common-tasks)
8. [Troubleshooting](#troubleshooting)

---

## System Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────┐
│              Swing + Long-Term Trading System                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   Data       │    │   Screening  │    │  Strategy    │  │
│  │  Ingestion   │───▶│   & Ranking  │───▶│   Engine     │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│         │                    │                    │         │
│         ▼                    ▼                    ▼         │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │  PostgreSQL  │    │   OpenAI     │    │  Telegram    │  │
│  │   Database   │    │   (AI Rank)  │    │  Notifier    │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │  Backtesting │    │   Order      │    │  Monitoring  │  │
│  │  Framework   │    │  Execution   │    │  & Metrics   │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │          SolidQueue (Job Scheduling)                 │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Technology Stack

- **Framework**: Rails 8.1 (API mode)
- **Language**: Ruby 3.3+
- **Database**: PostgreSQL 15+
- **Job Queue**: SolidQueue (DB-backed)
- **External APIs**: DhanHQ (market data, orders), OpenAI (AI ranking), Telegram (notifications)

---

## Core Components

### 1. Data Layer

**Models:**
- `Instrument` - Trading instruments (equity, index)
- `CandleSeriesRecord` - Historical candle data (daily, weekly)
- `Order` - Order tracking and audit trail
- `BacktestRun` / `BacktestPosition` - Backtesting results
- `OptimizationRun` - Parameter optimization results
- `Setting` - Key-value configuration store

**Data Ingestion:**
- `Candles::DailyIngestor` - Fetches and stores daily candles
- `Candles::WeeklyIngestor` - Aggregates and stores weekly candles
- `Candles::IntradayFetcher` - On-demand intraday data (in-memory)

### 2. Analysis Layer

**Indicators:**
- EMA (Exponential Moving Average)
- RSI (Relative Strength Index)
- MACD (Moving Average Convergence Divergence)
- ADX (Average Directional Index)
- Supertrend
- ATR (Average True Range)

**Smart Money Concepts (SMC):**
- BOS (Break of Structure)
- CHOCH (Change of Character)
- Order Blocks
- Fair Value Gaps (FVG)
- Mitigation Blocks
- `SMC::StructureValidator` - Holistic structure validation

### 3. Screening & Ranking

**Screeners:**
- `Screeners::SwingScreener` - Swing trading candidate identification
- `Screeners::LongTermScreener` - Long-term trading candidate identification
- `Screeners::AIRanker` - AI-powered ranking using OpenAI
- `Screeners::FinalSelector` - Final candidate selection with combined scores

### 4. Strategy Engine

**Signal Generation:**
- `Strategies::Swing::Engine` - Swing trading strategy engine
- `Strategies::Swing::SignalBuilder` - Signal construction with risk management
- `Strategies::Swing::Evaluator` - Candidate evaluation
- `Strategies::LongTerm::Evaluator` - Long-term strategy evaluation

**Order Execution:**
- `Strategies::Swing::Executor` - Order placement with risk checks
- `Dhan::Orders` - DhanHQ API wrapper
- `Orders::Approval` - Manual approval system for first 30 trades
- `Orders::ProcessApprovedJob` - Processes approved orders

### 5. Backtesting Framework

**Core Services:**
- `Backtesting::SwingBacktester` - Swing trading backtesting
- `Backtesting::LongTermBacktester` - Long-term trading backtesting
- `Backtesting::WalkForward` - Walk-forward analysis
- `Backtesting::Optimizer` - Parameter optimization
- `Backtesting::MonteCarlo` - Monte Carlo simulation
- `Backtesting::Portfolio` - Virtual portfolio management
- `Backtesting::Position` - Virtual position tracking

### 6. Job Scheduling

**Recurring Jobs** (via `config/recurring.yml`):
- Daily candle ingestion (07:30 IST)
- Weekly candle ingestion (Monday 07:30 IST)
- Swing screener (Weekdays 07:40 IST)
- Health monitoring (Every 30 minutes)
- Optional: Intraday fetcher, entry/exit monitors

### 7. Observability

**Monitoring:**
- `MonitorJob` - Health checks, queue monitoring, OpenAI cost tracking
- `Metrics::Tracker` - System metrics (API calls, job durations, orders, P&L)
- `Metrics::PnlTracker` - P&L tracking (realized/unrealized)

**Notifications:**
- `Telegram::Notifier` - Telegram alerts for signals, exits, errors
- `Telegram::AlertFormatter` - Message formatting with HTML

---

## Data Flow

### Daily Workflow

```
1. Daily Candle Ingestion (07:30 IST)
   └─> Fetches daily candles from DhanHQ
   └─> Stores in PostgreSQL (candle_series table)

2. Weekly Candle Ingestion (Monday 07:30 IST)
   └─> Aggregates daily candles into weekly
   └─> Stores in PostgreSQL (candle_series table)

3. Swing Screener (07:40 IST, Weekdays)
   └─> Loads universe from master_universe.yml
   └─> Filters by price, volume, trend
   └─> Calculates indicators (EMA, RSI, MACD, Supertrend, ADX)
   └─> Optional: SMC structure validation
   └─> Returns top 50 candidates

4. AI Ranking (Optional, if enabled)
   └─> Sends top candidates to OpenAI
   └─> Receives AI scores and analysis
   └─> Caches results (24h TTL)

5. Final Selection
   └─> Combines screener + AI scores
   └─> Returns top N candidates

6. Strategy Analysis (Optional, if auto_analyze enabled)
   └─> Evaluates candidates using Swing::Engine
   └─> Generates trading signals
   └─> Optional: SMC validation

7. Order Execution (Optional, if auto-execution enabled)
   └─> Validates signal
   └─> Checks risk limits
   └─> Checks circuit breakers
   └─> For first 30 trades: Requires manual approval
   └─> Places order via DhanHQ
   └─> Sends Telegram notification
```

### Order Approval Flow (First 30 Trades)

```
1. Signal Generated
   └─> Executor checks executed trade count
   └─> If < 30: Creates order with requires_approval=true
   └─> Sends Telegram approval request

2. Manual Approval
   └─> Review order details
   └─> Run: rails orders:approve[order_id]
   └─> Approval service updates order
   └─> Automatically enqueues ProcessApprovedJob

3. Order Placement
   └─> ProcessApprovedJob processes approved order
   └─> Places order via DhanHQ
   └─> Sends Telegram notification
```

---

## Key Workflows

### 1. Initial Setup

```bash
# 1. Clone and install
git clone <repo>
cd swing_long_trader
bundle install

# 2. Configure environment
cp .env.example .env
# Edit .env with your credentials

# 3. Setup database
rails db:create
rails db:migrate

# 4. Build universe
rails universe:build

# 5. Import instruments
rails instruments:import

# 6. Ingest historical candles
rails runner "Candles::DailyIngestor.call(days_back: 365)"
rails runner "Candles::WeeklyIngestor.call(weeks_back: 52)"
```

### 2. Daily Operations

```bash
# Check system health
rails runner "MonitorJob.perform_now"

# View metrics
rails metrics:daily

# Check pending approvals
rails orders:pending_approval

# Process approved orders
rails orders:process_approved

# Check job status
rails solid_queue:status
```

### 3. Running Backtests

```bash
# Swing trading backtest
rails backtest:swing[2024-01-01,2024-12-31,100000]

# Long-term backtest
rails backtest:long_term[2024-01-01,2024-12-31,100000]

# Walk-forward analysis
rails runner "Backtesting::WalkForward.call(...)"

# Parameter optimization
rails runner "Backtesting::Optimizer.call(...)"

# View results
rails backtest:list
rails backtest:show[run_id]
rails backtest:report[run_id]
```

### 4. Manual Trading (First 30 Trades)

```bash
# 1. Review pending approvals
rails orders:pending_approval

# 2. Approve order
rails orders:approve[order_id]

# 3. Check statistics
rails orders:stats

# 4. Monitor execution
rails orders:process_approved
```

---

## Configuration

### Main Configuration File

`config/algo.yml` - Central configuration for:
- Trading strategies (swing, long-term)
- Risk management (position sizing, stop loss, take profit)
- Indicators (EMA, RSI, MACD, Supertrend, ADX)
- SMC validation settings
- OpenAI cost monitoring
- Backtesting parameters
- Execution settings (manual approval, dry-run)

### Environment Variables

See [Environment Setup Guide](ENV_SETUP.md) for complete list:
- `DHANHQ_CLIENT_ID` / `DHANHQ_ACCESS_TOKEN` (Required)
- `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` (Optional)
- `OPENAI_API_KEY` (Optional)
- `DRY_RUN=true` (Enable dry-run mode)

### Job Scheduling

`config/recurring.yml` - SolidQueue recurring jobs:
- Daily/weekly candle ingestion
- Swing screener
- Health monitoring
- Optional: Entry/exit monitors, intraday fetcher

---

## Quick Reference

### Rake Tasks

**Instruments:**
- `rails instruments:import` - Import instruments from DhanHQ
- `rails instruments:status` - Show import statistics
- `rails instruments:clear` - Clear all instruments (use with caution)

**Universe:**
- `rails universe:build` - Build master universe from CSV files
- `rails universe:stats` - Show universe statistics
- `rails universe:validate` - Validate universe against imported instruments

**Candles:**
- `rails runner "Candles::DailyIngestor.call"` - Ingest daily candles
- `rails runner "Candles::WeeklyIngestor.call"` - Ingest weekly candles

**Indicators:**
- `rails indicators:test` - Test all indicators
- `rails indicators:test_ema` - Test specific indicator

**Backtesting:**
- `rails backtest:swing[from,to,capital]` - Run swing backtest
- `rails backtest:long_term[from,to,capital]` - Run long-term backtest
- `rails backtest:list` - List all backtest runs
- `rails backtest:show[run_id]` - Show backtest details
- `rails backtest:report[run_id]` - Generate backtest report
- `rails backtest:list_optimizations` - List optimization runs

**Orders:**
- `rails orders:pending_approval` - List pending approvals
- `rails orders:approve[order_id]` - Approve an order
- `rails orders:reject[order_id,reason]` - Reject an order
- `rails orders:stats` - Show approval statistics
- `rails orders:process_approved` - Process approved orders

**Risk Testing:**
- `rails test:risk:idempotency` - Test order idempotency
- `rails test:risk:exposure_limits` - Test exposure limits
- `rails test:risk:circuit_breakers` - Test circuit breakers
- `rails test:risk:all` - Run all risk tests

**Monitoring:**
- `rails metrics:daily` - Show daily metrics
- `rails metrics:weekly` - Show weekly metrics
- `rails solid_queue:status` - Show job queue status
- `rails solid_queue:failed` - List failed jobs

**Verification:**
- `rails verify:risks` - Verify all risk items
- `rails production:ready` - Check production readiness
- `rails production:checklist` - Show deployment checklist
- `rails hardening:check` - Run hardening checks

---

## Common Tasks

### Adding New Instruments

1. Add symbols to `config/universe/csv/your_universe.csv`
2. Run `rails universe:build`
3. Run `rails instruments:import`
4. Verify: `rails universe:validate`

### Running a Screener Manually

```ruby
# In Rails console
result = Screeners::SwingScreener.call
puts result[:candidates].first(10).map { |c| "#{c[:symbol]}: #{c[:score]}" }
```

### Generating a Signal

```ruby
# In Rails console
instrument = Instrument.find_by(symbol_name: 'RELIANCE')
daily_series = instrument.load_daily_candles
weekly_series = instrument.load_weekly_candles

result = Strategies::Swing::Engine.call(
  instrument: instrument,
  daily_series: daily_series,
  weekly_series: weekly_series
)

puts result[:signal] if result[:success]
```

### Testing Order Placement (Dry-Run)

```ruby
# In Rails console
signal = {
  instrument_id: instrument.id,
  symbol: 'RELIANCE',
  direction: :long,
  entry_price: 2500.0,
  qty: 10,
  stop_loss: 2300.0,
  take_profit: 2875.0,
  confidence: 80
}

result = Strategies::Swing::Executor.call(signal, dry_run: true)
puts result
```

### Checking System Health

```bash
# Run health check
rails runner "MonitorJob.perform_now"

# Check metrics
rails metrics:daily

# Check job queue
rails solid_queue:status

# Check for failed jobs
rails solid_queue:failed
```

---

## Troubleshooting

### Common Issues

**1. Instruments Not Importing**
```bash
# Check DhanHQ credentials
echo $DHANHQ_CLIENT_ID
echo $DHANHQ_ACCESS_TOKEN

# Check API connection
rails runner "DhanHQ::Models::MarketFeed.ltp('NSE_EQ')"

# Verify universe
rails universe:stats
```

**2. Candles Not Ingesting**
```bash
# Check instrument exists
rails runner "puts Instrument.count"

# Check DhanHQ API
rails runner "instrument = Instrument.first; puts instrument.historical_ohlc"

# Manually ingest
rails runner "Candles::DailyIngestor.call(instrument: Instrument.first, days_back: 30)"
```

**3. Screener Not Finding Candidates**
```bash
# Check candle data
rails runner "puts CandleSeriesRecord.where(timeframe: '1D').count"

# Check universe
rails universe:validate

# Run screener with debug
rails runner "result = Screeners::SwingScreener.call; puts result.inspect"
```

**4. Jobs Not Running**
```bash
# Check SolidQueue
rails solid_queue:status

# Check recurring.yml
cat config/recurring.yml

# Verify workers running
ps aux | grep solid_queue
```

**5. Orders Not Placing**
```bash
# Check approval status
rails orders:pending_approval

# Check dry-run mode
echo $DRY_RUN

# Check risk limits
rails test:risk:exposure_limits

# Check circuit breaker
rails test:risk:circuit_breakers
```

**6. Telegram Notifications Not Sending**
```bash
# Check credentials
echo $TELEGRAM_BOT_TOKEN
echo $TELEGRAM_CHAT_ID

# Test notification
rails runner "Telegram::Notifier.send_error_alert('Test message', context: 'Test')"
```

**7. OpenAI Costs Too High**
```bash
# Check current costs
rails metrics:daily

# Check thresholds
grep -A 5 "openai_cost_monitoring" config/algo.yml

# Disable AI ranking
# Edit config/algo.yml: swing_trading.ai_ranking.enabled: false
```

### Debug Mode

Enable verbose logging:
```ruby
# In config/environments/development.rb or production.rb
config.log_level = :debug
```

### Getting Help

1. Check [Runbook](runbook.md) for operational procedures
2. Check [Manual Verification Steps](MANUAL_VERIFICATION_STEPS.md) for testing
3. Check [Production Checklist](PRODUCTION_CHECKLIST.md) for deployment
4. Review logs: `tail -f log/development.log`

---

## Related Documentation

- **[README.md](../README.md)** - Local setup and quick start
- **[Architecture](architecture.md)** - Detailed system architecture
- **[Runbook](runbook.md)** - Operational procedures
- **[Backtesting Guide](BACKTESTING.md)** - Backtesting framework documentation
- **[Deployment Quickstart](DEPLOYMENT_QUICKSTART.md)** - Step-by-step deployment
- **[Environment Setup](ENV_SETUP.md)** - Environment variables guide
- **[Universe Setup](UNIVERSE_SETUP.md)** - Instrument universe configuration
- **[Production Checklist](PRODUCTION_CHECKLIST.md)** - Go-live checklist
- **[Manual Verification Steps](MANUAL_VERIFICATION_STEPS.md)** - Testing procedures

---

**Last Updated:** After completing all implementation phases

