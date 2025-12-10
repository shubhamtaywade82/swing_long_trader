# Swing + Long-Term Trading System

A comprehensive Rails-based algorithmic trading system for swing and long-term trading strategies in the Indian stock market.

## Features

- **Data Ingestion**: Daily and weekly candle data from DhanHQ API
- **Screening**: Multi-indicator technical analysis with AI-powered ranking
- **Strategy Engine**: Swing trading signal generation with risk management
- **Backtesting**: Comprehensive backtesting framework for strategy validation
- **Notifications**: Telegram alerts for signals, exits, and system events
- **Job Scheduling**: Automated daily/weekly operations via SolidQueue

## Prerequisites

- Ruby 3.3+
- Rails 8.1+
- PostgreSQL 15+
- DhanHQ API credentials
- Telegram Bot Token (optional, for notifications)
- OpenAI API Key (optional, for AI ranking)

## Setup

### 1. Clone and Install

```bash
git clone <repository-url>
cd swing_long_trader
bundle install
```

### 2. Configure Environment

```bash
cp .env.example .env
# Edit .env and add your credentials:
# - DHANHQ_CLIENT_ID
# - DHANHQ_ACCESS_TOKEN
# - TELEGRAM_BOT_TOKEN (optional)
# - TELEGRAM_CHAT_ID (optional)
# - OPENAI_API_KEY (optional)
```

### 3. Setup Database

```bash
rails db:create
rails db:migrate
```

### 4. Import Instruments

```bash
rails instruments:import
rails instruments:status
```

### 5. Ingest Historical Candles

```bash
rails candles:daily:ingest
rails candles:weekly:ingest
```

## Usage

### Running Screeners

```bash
# Run swing screener
rails screener:swing

# Run with AI ranking
rails screener:swing:with_ai
```

### Running Backtests

```bash
# Run swing trading backtest
rails backtest:swing[2024-01-01,2024-12-31,100000]

# List backtest runs
rails backtest:list

# Show backtest details
rails backtest:show[1]
```

### Viewing Metrics

```bash
# Daily metrics
rails metrics:daily

# Weekly metrics
rails metrics:weekly
```

## Architecture

See [docs/architecture.md](docs/architecture.md) for detailed architecture documentation.

## Configuration

Main configuration file: `config/algo.yml`

Key settings:
- Swing trading parameters
- Indicator configurations
- Risk management settings
- Notification preferences

## Jobs & Scheduling

Jobs are scheduled via `config/recurring.yml`:
- Daily candle ingestion: 07:30 IST
- Weekly candle ingestion: 07:30 IST (Monday)
- Swing screener: 07:40 IST (weekdays)
- Health monitoring: Every 30 minutes

## Testing

```bash
# Run all tests
rails test

# Run specific test
rails test test/models/instrument_test.rb
```

## Documentation

- [Architecture](docs/architecture.md)
- [Runbook](docs/runbook.md)
- [Migration Guide](docs/SWING_LONG_TRADER_MIGRATION_GUIDE.md)
- [Implementation TODO](docs/IMPLEMENTATION_TODO.md)

## License

[Your License Here]
