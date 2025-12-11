# Deployment Quickstart Guide

**Step-by-step guide to deploy and verify the Swing + Long-Term Trading System**

---

## Prerequisites

- [ ] Ruby 3.3+ installed
- [ ] PostgreSQL 15+ installed and running
- [ ] DhanHQ API credentials (Client ID, Access Token)
- [ ] Telegram Bot Token and Chat ID (optional, for notifications)
- [ ] OpenAI API Key (optional, for AI ranking)

---

## Step 1: Initial Setup

### 1.1 Clone and Install

```bash
# Clone repository
git clone <repository-url>
cd swing_long_trader

# Install dependencies
bundle install

# Create database
rails db:create
rails db:migrate
```

### 1.2 Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit .env with your credentials
# Required: DHANHQ_CLIENT_ID, DHANHQ_ACCESS_TOKEN
# Optional: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, OPENAI_API_KEY
```

See [Environment Setup Guide](ENV_SETUP.md) for detailed instructions.

---

## Step 2: Universe Setup

### 2.1 Create Universe CSV

```bash
# Create your universe CSV file
# Place it in: config/universe/csv/your_universe.csv
# Format: One column named "Symbol" with instrument symbols
```

Example:
```csv
Symbol
NIFTY
BANKNIFTY
RELIANCE
TCS
INFY
```

### 2.2 Build Master Universe

```bash
# Build master universe from CSV files
rails universe:build

# Verify universe
rails universe:stats
```

See [Universe Setup Guide](UNIVERSE_SETUP.md) for details.

---

## Step 3: Import Instruments

### 3.1 Import Instruments

```bash
# Import instruments from DhanHQ
rails instruments:import

# Check import status
rails instruments:status

# Validate universe against imported instruments
rails universe:validate
```

**Note:** This requires DhanHQ API credentials and may take several minutes.

---

## Step 4: Ingest Historical Candles

### 4.1 Daily Candles

```bash
# Ingest daily candles for all instruments
rails runner "Candles::DailyIngestor.call(days_back: 365)"

# Or use the job
rails runner "Candles::DailyIngestorJob.perform_now"
```

### 4.2 Weekly Candles

```bash
# Ingest weekly candles (aggregated from daily)
rails runner "Candles::WeeklyIngestor.call(weeks_back: 52)"

# Or use the job
rails runner "Candles::WeeklyIngestorJob.perform_now"
```

### 4.3 Verify Data

```bash
# Check candle counts
rails runner "
  puts 'Daily candles: ' + CandleSeriesRecord.where(timeframe: '1D').count.to_s
  puts 'Weekly candles: ' + CandleSeriesRecord.where(timeframe: '1W').count.to_s
"
```

---

## Step 5: Test Core Functionality

### 5.1 Test Indicators

```bash
# Test all indicators
rails indicators:test

# Test specific indicator
rails indicators:test_ema
rails indicators:test_rsi
rails indicators:test_supertrend
```

### 5.2 Test Screener

```bash
# Run swing screener
rails runner "
  result = Screeners::SwingScreener.call
  puts 'Candidates found: ' + result[:candidates].size.to_s
  puts 'Top 5:'
  result[:candidates].first(5).each { |c| puts \"  - #{c[:symbol]}: #{c[:score]}\" }
"
```

### 5.3 Test Telegram Notifications (Optional)

```bash
# Send test notification
rails runner "
  Telegram::Notifier.send_daily_candidates(
    candidates: [{symbol: 'RELIANCE', score: 85}],
    timestamp: Time.current
  )
"
```

---

## Step 6: Configure Jobs

### 6.1 Review Job Schedules

Edit `config/recurring.yml` to configure job schedules:

```yaml
production:
  daily_candle_ingestion:
    class: Candles::DailyIngestorJob
    schedule: "0 7:30 * * *" # 07:30 IST daily

  swing_screener:
    class: Screeners::SwingScreenerJob
    schedule: "0 7:40 * * 1-5" # 07:40 IST weekdays
```

### 6.2 Start SolidQueue Workers

```bash
# In production, use a process manager (systemd, supervisor, etc.)
# For development/testing:
bundle exec rake solid_queue:start
```

---

## Step 7: Production Deployment

### 7.1 Pre-Deployment Checks

```bash
# Run hardening checks
rails hardening:check

# Check for secrets in code
rails hardening:secrets

# Verify database indexes
rails hardening:indexes

# Verify risk items
rails verify:risks
```

### 7.2 Deploy Application

```bash
# Set production environment variables
export RAILS_ENV=production
export DATABASE_URL=postgresql://user:pass@host/dbname

# Run migrations
rails db:migrate

# Precompile assets (if any)
rails assets:precompile

# Start application server
rails server

# Start SolidQueue workers
bundle exec rake solid_queue:start
```

### 7.3 Verify Deployment

```bash
# Check health
rails runner "MonitorJob.perform_now"

# Check metrics
rails metrics:daily

# Check SolidQueue status
rails solid_queue:status
```

---

## Step 8: Enable Dry-Run Mode (Recommended for First Week)

### 8.1 Enable Dry-Run

```bash
# Set environment variable
export DRY_RUN=true

# Or in config/algo.yml, set:
# execution:
#   dry_run: true
```

### 8.2 Monitor for First Week

- Watch job execution logs
- Monitor API usage
- Check error logs
- Verify notifications
- Review generated signals

---

## Step 9: Manual Trading Validation (First 30 Trades)

### 9.1 Review Signals

```bash
# Check recent signals (if stored)
rails runner "
  # Review signals generated by screener
  # Manually approve before execution
"
```

### 9.2 Execute Orders Manually

For the first 30 trades:
1. Review each signal
2. Manually approve execution
3. Monitor order placement
4. Track P&L

### 9.3 Enable Auto-Execution (After Validation)

After validating 30+ trades:
1. Disable dry-run mode
2. Enable auto-execution in `config/algo.yml`
3. Monitor closely for first week

---

## Step 10: Ongoing Operations

### 10.1 Daily Monitoring

```bash
# Check daily metrics
rails metrics:daily

# Check job status
rails solid_queue:status

# Check failed jobs
rails solid_queue:failed
```

### 10.2 Weekly Review

```bash
# Weekly metrics
rails metrics:weekly

# Review backtest results
rails backtest:list

# Review optimization results
rails backtest:list_optimizations
```

### 10.3 Maintenance

```bash
# Clean old jobs (if needed)
rails runner "SolidQueue::Job.clear_finished_in_batches"

# Update universe (if needed)
rails universe:build

# Re-import instruments (if needed)
rails instruments:import
```

---

## Troubleshooting

### Jobs Not Running

```bash
# Check SolidQueue status
rails solid_queue:status

# Check for failed jobs
rails solid_queue:failed

# Restart workers
# (Stop and restart SolidQueue workers)
```

### API Rate Limits

- DhanHQ: Check rate limits in API documentation
- OpenAI: Limited to 50 calls/day (configurable)
- Monitor usage: `rails metrics:daily`

### Database Issues

```bash
# Check database connection
rails db:version

# Check pending migrations
rails db:migrate:status

# Backup database
pg_dump swing_long_trader_production > backup.sql
```

### Missing Candles

```bash
# Re-ingest for specific instrument
rails runner "
  instrument = Instrument.find_by(symbol_name: 'RELIANCE')
  Candles::DailyIngestor.call(instrument: instrument, days_back: 365)
"
```

---

## Next Steps

1. **Run Backtests**: See [Backtesting Guide](BACKTESTING.md)
2. **Review Architecture**: See [Architecture Documentation](architecture.md)
3. **Operational Procedures**: See [Runbook](runbook.md)
4. **Production Checklist**: See [Production Checklist](PRODUCTION_CHECKLIST.md)

---

## Support

For issues or questions:
- Check [Manual Verification Steps](MANUAL_VERIFICATION_STEPS.md)
- Review [Runbook](runbook.md) for operational procedures
- Review [Architecture Documentation](architecture.md) for system design

---

**Last Updated:** After completing all implementation phases

