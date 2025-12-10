# System Architecture

## Overview

The Swing + Long-Term Trading System is a Rails-based monolith that provides end-to-end algorithmic trading capabilities for swing and long-term trading strategies.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Swing Trading System                      │
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
│  ┌──────────────┐    ┌──────────────┐                      │
│  │ Backtesting  │    │   DhanHQ     │                      │
│  │  Framework   │    │    API       │                      │
│  └──────────────┘    └──────────────┘                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Data Layer

**Models:**
- `Instrument` - Trading instruments (stocks, indices)
- `CandleSeriesRecord` - Historical OHLCV data
- `BacktestRun` - Backtest execution records
- `BacktestPosition` - Individual trade records
- `Setting` - Key-value configuration store

**Database:**
- PostgreSQL for all persistent data
- SolidQueue tables for job management
- SolidCache for caching

### 2. Data Ingestion

**Services:**
- `Candles::DailyIngestor` - Fetches and stores daily candles
- `Candles::WeeklyIngestor` - Fetches and aggregates weekly candles
- `Candles::IntradayFetcher` - On-demand intraday data (in-memory)
- `Candles::Loader` - Loads candles from DB to CandleSeries format

**Jobs:**
- `Candles::DailyIngestorJob` - Scheduled daily at 07:30 IST
- `Candles::WeeklyIngestorJob` - Scheduled weekly on Monday

### 3. Screening & Ranking

**Services:**
- `Screeners::SwingScreener` - Technical analysis screening
- `Screeners::LongtermScreener` - Long-term strategy screening
- `Screeners::AIRanker` - AI-powered candidate ranking
- `Screeners::FinalSelector` - Combines screener + AI scores

**Process:**
1. Filter instruments by universe
2. Apply technical filters (EMA, Supertrend, ADX, RSI, MACD)
3. Score candidates (0-100)
4. AI ranking (optional)
5. Select top N candidates

### 4. Strategy Engine

**Services:**
- `Strategies::Swing::Engine` - Main strategy orchestrator
- `Strategies::Swing::SignalBuilder` - Generates trading signals
- `Strategies::Swing::Evaluator` - Evaluates screener candidates
- `Strategies::Swing::AIEvaluator` - AI evaluation of signals

**Signal Format:**
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

### 5. Backtesting

**Services:**
- `Backtesting::SwingBacktester` - Walk-forward backtesting
- `Backtesting::DataLoader` - Loads historical data
- `Backtesting::Portfolio` - Virtual portfolio manager
- `Backtesting::Position` - Position tracker
- `Backtesting::ResultAnalyzer` - Performance metrics

**Features:**
- No look-ahead bias (walk-forward)
- Entry/exit signal detection
- Position management
- Comprehensive performance metrics

### 6. Notifications

**Services:**
- `Telegram::Notifier` - Main notification service
- `Telegram::AlertFormatter` - Message formatting

**Alert Types:**
- Daily candidate lists
- Signal alerts
- Exit alerts
- Portfolio snapshots
- Error alerts

### 7. Job Scheduling

**Jobs:**
- `Candles::DailyIngestorJob`
- `Candles::WeeklyIngestorJob`
- `Screeners::SwingScreenerJob`
- `Screeners::AIRankerJob`
- `Strategies::Swing::AnalysisJob`
- `MonitorJob`

**Scheduling:**
- Configured in `config/recurring.yml`
- Managed by SolidQueue

## Data Flow

### Daily Workflow

1. **07:30 IST** - Daily candle ingestion
2. **07:30 IST (Monday)** - Weekly candle ingestion
3. **07:40 IST** - Swing screener runs
4. **07:45 IST** - AI ranking (if enabled)
5. **07:50 IST** - Strategy analysis
6. **Every 30min** - Health monitoring

### Signal Generation Flow

```
Instruments → Screener → AI Ranker → Strategy Engine → Signals → Telegram
```

### Backtesting Flow

```
Historical Data → Data Loader → Backtester → Portfolio → Result Analyzer → Database
```

## Technology Stack

- **Framework**: Rails 8.1 (API mode)
- **Database**: PostgreSQL 15+
- **Job Queue**: SolidQueue (DB-backed)
- **Cache**: SolidCache (DB-backed)
- **APIs**: DhanHQ (market data), OpenAI (AI ranking)
- **Notifications**: Telegram Bot API
- **Testing**: Minitest, FactoryBot, WebMock, VCR

## Security

- API keys stored in environment variables
- No secrets in code
- Input validation on all services
- SQL injection prevention (ActiveRecord)
- Rate limiting on API calls

## Scalability

- Batch processing for large datasets
- Efficient database queries (includes, eager_load)
- Caching for frequently accessed data
- Job queue for async operations
- Database indexes for performance

## Monitoring

- Metrics tracking (API calls, job durations, failures)
- Structured logging
- Health checks
- Telegram alerts for critical events

