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

Before you begin, ensure you have the following installed:

- **Ruby 3.3+** - Check with `ruby -v`
- **Rails 8.1+** - Check with `rails -v`
- **PostgreSQL 15+** - Check with `psql --version`
- **Bundler** - Check with `bundle -v`
- **Git** - For cloning the repository

### API Credentials Required

- **DhanHQ API credentials** (Required)
  - Get from: https://dhan.co/
  - You'll need: `CLIENT_ID` and `ACCESS_TOKEN`

- **Telegram Bot Token** (Optional, for notifications)
  - Create bot via @BotFather on Telegram
  - Get chat ID by messaging your bot

- **OpenAI API Key** (Optional, for AI-powered ranking)
  - Get from: https://platform.openai.com/api-keys

## Local Setup Guide

### Step 1: Clone the Repository

```bash
git clone <repository-url>
cd swing_long_trader
```

### Step 2: Install Dependencies

```bash
# Install Ruby gems
bundle install

# Install Node.js dependencies (if any)
yarn install
```

### Step 3: Configure Environment Variables

```bash
# Copy the example environment file
cp .env.example .env

# Edit .env with your favorite editor
nano .env  # or vim .env or code .env
```

**Minimum required variables to set:**
```bash
DHANHQ_CLIENT_ID=your_client_id_here
DHANHQ_ACCESS_TOKEN=your_access_token_here
```

**Optional but recommended:**
```bash
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here
OPENAI_API_KEY=your_openai_key_here
```

See [docs/ENVIRONMENT_VARIABLES.md](docs/ENVIRONMENT_VARIABLES.md) for complete list of environment variables.

### Step 4: Setup Database

```bash
# Create the database
rails db:create

# Run migrations
rails db:migrate

# (Optional) Load seed data
rails db:seed
```

**Verify database connection:**
```bash
rails db:version
```

### Step 5: Import Trading Instruments

The system needs instrument master data (stocks, indices) to operate.

```bash
# Import instruments from CSV
rails instruments:import

# Check import status
rails instruments:status
```

**Note:** You'll need instrument CSV files in `config/universe/csv/` directory. See [docs/runbook.md](docs/runbook.md) for details.

### Step 6: Ingest Historical Candle Data

Historical data is required for indicators and backtesting.

```bash
# Ingest daily candles (last 365 days by default)
rails candles:daily:ingest

# Ingest weekly candles (last 52 weeks by default)
rails candles:weekly:ingest

# Check candle data status
rails candles:status
```

**Note:** This may take some time depending on the number of instruments. The system will fetch data from DhanHQ API.

### Step 7: Verify Setup

Run these commands to verify everything is working:

```bash
# Check system health
rails hardening:check

# Test indicators
rails indicators:test

# View daily metrics
rails metrics:daily
```

### Step 8: (Optional) Start Background Jobs

For automated daily operations, start SolidQueue workers:

```bash
# Start SolidQueue worker (in a separate terminal)
bin/rails solid_queue:start

# Or use Foreman (if using Procfile.dev)
foreman start
```

Jobs are scheduled via `config/recurring.yml`. See [Jobs & Scheduling](#jobs--scheduling) section below.

## Troubleshooting

### Database Connection Issues

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql  # Linux
brew services list | grep postgresql  # macOS

# Verify database exists
rails db:version
```

### Missing Dependencies

```bash
# Reinstall gems
bundle install

# Check for missing system dependencies
bundle exec rails --version
```

### API Connection Issues

```bash
# Verify environment variables are loaded
rails runner "puts ENV['DHANHQ_CLIENT_ID']"

# Test DhanHQ connection (in Rails console)
rails console
> Instrument.first.ltp  # Should return current price
```

### Candle Ingestion Fails

- Check DhanHQ API credentials are correct
- Verify API rate limits haven't been exceeded
- Check network connectivity
- Review logs: `tail -f log/development.log`

## Usage

### Running Screeners

```bash
# Run swing screener (technical analysis only)
rails screener:swing

# Run swing screener with AI ranking (requires OpenAI API key)
rails screener:swing:with_ai

# Run long-term screener
rails screener:longterm
```

**Note:** Screeners require sufficient historical candle data. Ensure you've completed Step 6 of setup.

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
# Daily metrics (today)
rails metrics:daily

# Daily metrics for specific date
DATE=2024-01-15 rails metrics:daily

# Weekly metrics summary
rails metrics:weekly
```

### Managing Universe

```bash
# Build universe from CSV files
rails universe:build

# View universe statistics
rails universe:stats

# Validate universe
rails universe:validate
```

### Testing Indicators

```bash
# Test all indicators
rails indicators:test

# Test specific indicator
rails indicators:test_ema
rails indicators:test_rsi
rails indicators:test_supertrend
rails indicators:test_adx
rails indicators:test_macd
rails indicators:test_atr
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

Jobs are scheduled via `config/recurring.yml` using SolidQueue's recurring jobs feature.

### Scheduled Jobs

- **Daily candle ingestion**: 07:30 IST (every day)
- **Weekly candle ingestion**: 07:30 IST (Monday only)
- **Swing screener**: 07:40 IST (weekdays only)
- **Health monitoring**: Every 30 minutes

### Starting Background Workers

```bash
# Start SolidQueue worker
bin/rails solid_queue:start

# Or use Foreman (recommended for development)
foreman start -f Procfile.dev
```

### Manual Job Execution

```bash
# Run daily candle ingestion manually
rails runner "Candles::DailyIngestorJob.perform_now"

# Run swing screener manually
rails runner "Screeners::SwingScreenerJob.perform_now"
```

## Testing

```bash
# Run all tests
rails test

# Run specific test
rails test test/models/instrument_test.rb
```

## Development

### Running Tests

```bash
# Run all tests
rails test

# Run specific test file
rails test test/models/instrument_test.rb

# Run tests with coverage (if configured)
COVERAGE=true rails test
```

### Code Quality

```bash
# Run RuboCop
bundle exec rubocop

# Run Brakeman (security scan)
bundle exec brakeman

# Run Bundler Audit
bundle exec bundler-audit check
```

### Rails Console

```bash
# Start Rails console
rails console

# Example: Check instrument data
> Instrument.count
> Instrument.first.load_daily_candles(limit: 10)
```

## Documentation

- **[System Overview](docs/SYSTEM_OVERVIEW.md)** - Complete system guide, quick reference, and troubleshooting
- **[Implementation Summary](docs/IMPLEMENTATION_SUMMARY.md)** - Complete implementation summary and status
- **[Architecture](docs/architecture.md)** - System architecture and component overview
- **[Runbook](docs/runbook.md)** - Operational procedures and troubleshooting
- **[Environment Variables](docs/ENVIRONMENT_VARIABLES.md)** - Complete list of environment variables
- **[Production Checklist](docs/PRODUCTION_CHECKLIST.md)** - Pre-deployment checklist
- **[Deployment Quickstart](docs/DEPLOYMENT_QUICKSTART.md)** - Step-by-step deployment guide
- **[Backtesting Guide](docs/BACKTESTING.md)** - Comprehensive backtesting documentation
- **[Migration Guide](docs/SWING_LONG_TRADER_MIGRATION_GUIDE.md)** - Migration from AlgoScalperAPI
- **[Implementation TODO](docs/IMPLEMENTATION_TODO.md)** - Development progress tracker

## License

[Your License Here]
