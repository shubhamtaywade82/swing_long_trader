# Getting Started Guide

**Complete step-by-step guide to get the Swing + Long-Term Trading System up and running**

---

## 🎯 Overview

This guide will walk you through setting up the Swing + Long-Term Trading System from scratch. By the end, you'll have:
- ✅ System installed and configured
- ✅ Instruments imported
- ✅ Historical data ingested
- ✅ System verified and ready for use

**Estimated Time:** 30-60 minutes (depending on data ingestion)

---

## 📋 Prerequisites

Before you begin, ensure you have:

### Required Software
- **Ruby 3.3+** - `ruby -v`
- **Rails 8.1+** - `rails -v`
- **PostgreSQL 15+** - `psql --version`
- **Bundler** - `bundle -v`
- **Git** - `git --version`

### Required API Credentials
- **DhanHQ API** (Required)
  - Get from: https://dhan.co/
  - You'll need: `CLIENT_ID` and `ACCESS_TOKEN`

### Optional API Credentials
- **Telegram Bot** (Optional, for notifications)
  - Create via @BotFather on Telegram
  - Get `BOT_TOKEN` and `CHAT_ID`

- **OpenAI API** (Optional, for AI ranking)
  - Get from: https://platform.openai.com/api-keys

---

## 🚀 Step-by-Step Setup

### Step 1: Clone and Install (5 minutes)

```bash
# Clone the repository
git clone <repository-url>
cd swing_long_trader

# Install Ruby dependencies
bundle install

# Create and setup database
rails db:create
rails db:migrate
```

**Verify:** Run `rails -v` and `rails db:version` to confirm setup.

---

### Step 2: Configure Environment (5 minutes)

```bash
# Copy example environment file
cp .env.example .env

# Edit .env with your credentials
nano .env  # or use your preferred editor
```

**Required Variables:**
```bash
DHANHQ_CLIENT_ID=your_client_id
DHANHQ_ACCESS_TOKEN=your_access_token
```

**Optional Variables:**
```bash
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=your_chat_id
OPENAI_API_KEY=your_openai_key
DRY_RUN=true  # Enable dry-run mode for safety
```

**Verify:** Check that variables are loaded:
```bash
rails runner "puts ENV['DHANHQ_CLIENT_ID']"
```

See [Environment Setup Guide](ENV_SETUP.md) for detailed instructions.

---

### Step 3: Create Universe CSV (5 minutes)

Create your trading universe by creating a CSV file:

```bash
# Create universe directory if it doesn't exist
mkdir -p config/universe/csv

# Create your universe CSV
nano config/universe/csv/my_universe.csv
```

**CSV Format:**
```csv
Symbol
NIFTY
BANKNIFTY
RELIANCE
TCS
INFY
HDFCBANK
ICICIBANK
```

**Note:** Add symbols you want to trade. You can start with a small set (10-20 symbols) for testing.

**Verify:** Check CSV file exists:
```bash
ls -la config/universe/csv/
```

See [Universe Setup Guide](UNIVERSE_SETUP.md) for details.

---

### Step 4: Build Master Universe (2 minutes)

```bash
# Build master universe from CSV files
rails universe:build

# Verify universe was created
rails universe:stats
```

**Expected Output:**
```
Universe Statistics:
  Total Symbols: 7
  Source Files: 1
  Last Updated: 2024-12-12 10:00:00
```

**Verify:** Check master universe file:
```bash
ls -la config/universe/master_universe.yml
```

---

### Step 5: Import Instruments (10-15 minutes)

```bash
# Import instruments from DhanHQ
rails instruments:import
```

**What This Does:**
- Downloads instrument master from DhanHQ
- Imports all available instruments (equity, index, etc.)
- Stores in database for use by the system

**Expected Output:**
```
Importing instruments...
Processing NSE_EQ...
Processing NSE_INDEX...
...
Import completed successfully
Total instruments: 1500+
```

**Verify Import:**
```bash
# Check import status
rails instruments:status

# Validate universe against imported instruments
rails universe:validate

# Check in console
rails console
> Instrument.count
> Instrument.find_by(symbol_name: 'RELIANCE')
```

**Troubleshooting:**
- If import fails, verify DhanHQ credentials
- Check network connectivity
- Ensure database is accessible

---

### Step 6: Ingest Historical Candles (15-30 minutes)

```bash
# Ingest daily candles (last 365 days)
rails runner "Candles::DailyIngestor.call(days_back: 365)"

# Ingest weekly candles (last 52 weeks)
rails runner "Candles::WeeklyIngestor.call(weeks_back: 52)"
```

**What This Does:**
- Fetches historical daily candles for all instruments in universe
- Aggregates daily candles into weekly candles
- Stores in database for analysis

**Expected Output:**
```
Ingesting daily candles...
Processing RELIANCE...
Processing TCS...
...
Ingestion completed
Total candles ingested: 5000+
```

**Verify Ingestion:**
```bash
rails console
> instrument = Instrument.find_by(symbol_name: 'RELIANCE')
> daily = instrument.load_daily_candles(limit: 10)
> puts daily.size  # Should be 10
> weekly = instrument.load_weekly_candles(limit: 10)
> puts weekly.size  # Should be 10
```

**Note:** This step may take 15-30 minutes depending on:
- Number of instruments in universe
- Historical data availability
- API rate limits

---

### Step 7: Verify System (5 minutes)

```bash
# Run complete verification workflow
rails verification:workflow

# Or run individual checks
rails verify:complete
rails verify:risks
rails verify:health
rails production:ready
```

**Expected Output:**
```
✅ System completeness check passed
✅ Risk verification passed
✅ Production readiness check passed
✅ All health checks passed
```

**Verify Components:**
```bash
# Check system status
rails verify:status

# Check database
rails runner "puts Instrument.count"
rails runner "puts CandleSeriesRecord.count"

# Check configuration
rails test:dry_run:check
```

---

### Step 8: Test System (5 minutes)

```bash
# Test all alert types (if Telegram configured)
rails test:alerts:all

# Test risk controls
rails test:risk:all

# Run screener manually
rails console
> result = Screeners::SwingScreener.call
> puts result[:candidates].first(5)
```

**Expected Output:**
```
Screening candidates...
Found 15 candidates
Top candidates:
  RELIANCE: 85.5
  TCS: 82.3
  ...
```

---

## ✅ Setup Complete!

Congratulations! Your system is now set up and ready to use.

### What's Next?

1. **Run Your First Screener**
   ```bash
   rails runner "result = Screeners::SwingScreener.call; puts result[:candidates].first(10)"
   ```

2. **Run a Backtest**
   ```bash
   rails backtest:swing[2024-01-01,2024-12-31,100000]
   ```

3. **Enable Automated Jobs** (Optional)
   - Configure `config/recurring.yml`
   - Start SolidQueue workers
   - See [Deployment Quickstart](DEPLOYMENT_QUICKSTART.md)

4. **Review Documentation**
   - [System Overview](SYSTEM_OVERVIEW.md) - Complete system guide
   - [Runbook](runbook.md) - Operational procedures
   - [Backtesting Guide](BACKTESTING.md) - Backtesting framework

---

## 🔧 Common Commands

### Daily Operations
```bash
# Run screener
rails runner "Screeners::SwingScreenerJob.perform_now"

# Check metrics
rails metrics:daily

# Check job status
rails solid_queue:status
```

### Backtesting
```bash
# Run swing backtest
rails backtest:swing[2024-01-01,2024-12-31,100000]

# List backtest runs
rails backtest:list

# View backtest results
rails backtest:show[run_id]
```

### Verification
```bash
# Complete verification
rails verification:workflow

# Health check
rails verify:health

# Test alerts
rails test:alerts:all
```

---

## 🐛 Troubleshooting

### Issue: Instruments Not Importing
```bash
# Check credentials
echo $DHANHQ_CLIENT_ID
echo $DHANHQ_ACCESS_TOKEN

# Test API connection
rails runner "DhanHQ::Models::MarketFeed.ltp('NSE_EQ')"
```

### Issue: Candles Not Ingesting
```bash
# Check instrument exists
rails runner "puts Instrument.count"

# Check manually
rails runner "instrument = Instrument.first; puts instrument.historical_ohlc"
```

### Issue: Screener Not Finding Candidates
```bash
# Check candle data
rails runner "puts CandleSeriesRecord.where(timeframe: '1D').count"

# Run with debug
rails runner "result = Screeners::SwingScreener.call; puts result.inspect"
```

### Issue: Jobs Not Running
```bash
# Check SolidQueue
rails solid_queue:status

# Check workers
ps aux | grep solid_queue
```

See [System Overview - Troubleshooting](SYSTEM_OVERVIEW.md#troubleshooting) for more.

---

## 📚 Additional Resources

- **[System Overview](SYSTEM_OVERVIEW.md)** - Complete system guide
- **[Architecture](architecture.md)** - System architecture
- **[Runbook](runbook.md)** - Operational procedures
- **[Backtesting Guide](BACKTESTING.md)** - Backtesting framework
- **[Deployment Quickstart](DEPLOYMENT_QUICKSTART.md)** - Production deployment
- **[Environment Setup](ENV_SETUP.md)** - Environment variables
- **[Universe Setup](UNIVERSE_SETUP.md)** - Instrument universe
- **[Production Checklist](PRODUCTION_CHECKLIST.md)** - Go-live checklist
- **[Manual Verification Steps](MANUAL_VERIFICATION_STEPS.md)** - Testing procedures
- **[Final Status](FINAL_STATUS.md)** - Implementation status

---

## 🎊 Success!

You're all set! The Swing + Long-Term Trading System is ready to use.

**Next Steps:**
1. Review the [System Overview](SYSTEM_OVERVIEW.md)
2. Run your first screener
3. Test with a backtest
4. Configure automated jobs (optional)
5. Review [Production Checklist](PRODUCTION_CHECKLIST.md) before going live

---

**Last Updated:** After completing all implementation phases

