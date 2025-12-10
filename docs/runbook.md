# Operational Runbook

## Daily Operations

### Morning Routine (Before Market Open)

1. **Check System Health**
   ```bash
   rails monitor:health
   ```

2. **Verify Candle Ingestion**
   ```bash
   rails candles:status
   ```

3. **Review Previous Day's Metrics**
   ```bash
   rails metrics:daily DATE=$(date -d yesterday +%Y-%m-%d)
   ```

### After Market Close

1. **Review Daily Candidates**
   - Check Telegram for daily candidate list
   - Review signals generated

2. **Check Job Status**
   ```bash
   rails jobs:status
   ```

## Manual Operations

### Import Instruments

```bash
# Full import
rails instruments:import

# Reimport (clears existing)
rails instruments:reimport

# Check status
rails instruments:status
```

### Ingest Candles

```bash
# Daily candles
rails candles:daily:ingest

# Weekly candles
rails candles:weekly:ingest

# Check candle status
rails candles:status
```

### Run Screeners Manually

```bash
# Swing screener
rails screener:swing

# With AI ranking
rails screener:swing:with_ai
```

### Run Backtests

```bash
# Swing backtest
rails backtest:swing[2024-01-01,2024-12-31,100000]

# View results
rails backtest:list
rails backtest:show[run_id]
```

## Troubleshooting

### Jobs Not Running

1. Check SolidQueue status:
   ```bash
   rails solid_queue:status
   ```

2. Check job queue:
   ```bash
   rails jobs:queue
   ```

3. Restart SolidQueue worker:
   ```bash
   bin/rails solid_queue:start
   ```

### API Rate Limits

If hitting DhanHQ rate limits:
1. Check metrics: `rails metrics:daily`
2. Reduce batch sizes in jobs
3. Add delays between API calls

### Database Issues

```bash
# Check database connection
rails db:version

# Reset database (WARNING: deletes all data)
rails db:reset

# Run migrations
rails db:migrate
```

### Telegram Notifications Not Working

1. Verify credentials in `.env`
2. Test connection:
   ```bash
   rails console
   > TelegramNotifier.send_message("Test message")
   ```

## Emergency Procedures

### Stop All Auto-Execution

1. Disable recurring jobs:
   ```bash
   # Comment out jobs in config/recurring.yml
   ```

2. Stop SolidQueue workers:
   ```bash
   pkill -f solid_queue
   ```

### Rebuild Universe

```bash
# Add CSV files to config/universe/csv/
# Then rebuild:
rails universe:build
rails universe:validate
```

### Clear Cache

```bash
rails cache:clear
```

## Monitoring

### Key Metrics to Watch

- DhanHQ API call count (should be < 1000/day)
- OpenAI API call count (should be < 50/day)
- Failed job count (should be 0)
- Job durations (should be reasonable)
- Candle freshness (should be < 2 days old)

### Alerts

System automatically sends Telegram alerts for:
- Job failures
- API errors
- Health check failures
- High error rates

## Backup & Recovery

### Database Backup

```bash
# Create backup
pg_dump swing_long_trader_production > backup_$(date +%Y%m%d).sql

# Restore backup
psql swing_long_trader_production < backup_YYYYMMDD.sql
```

### Configuration Backup

```bash
# Backup config files
tar -czf config_backup_$(date +%Y%m%d).tar.gz config/
```

## Maintenance

### Weekly Tasks

1. Review backtest results
2. Check system metrics
3. Verify candle data completeness
4. Review error logs

### Monthly Tasks

1. Run comprehensive backtests
2. Review and optimize strategy parameters
3. Update universe if needed
4. Review and clean old data

