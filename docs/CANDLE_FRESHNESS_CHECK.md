# Candle Freshness Check System

## Overview

The candle freshness check system ensures that candles are up-to-date before any analysis or screening operations. This prevents stale data from being used in trading decisions.

## How It Works

### Automatic Freshness Check

The system automatically checks candle freshness when:
1. **Swing Screener** runs - checks daily candles
2. **Longterm Screener** runs - checks both daily and weekly candles
3. **Multi-Timeframe Analyzer** runs - checks freshness (logs warning, doesn't auto-ingest)

### Freshness Criteria

- **Default Max Age**: 1 day (candles should be at least from yesterday)
- **Default Min Freshness**: 80% of instruments must have fresh candles
- **Timeframe Support**: Daily (1D) and Weekly (1W)

### Auto-Ingestion

When candles are detected as stale:
- **In Screeners**: Automatically triggers ingestion for the stale timeframe
- **In Analysis**: Only logs warning (doesn't auto-ingest to avoid blocking)
- **In Tests**: Auto-ingestion is disabled by default

## Usage

### Manual Check

```bash
# Check freshness and auto-ingest if stale
rails candles:check_freshness
```

### Programmatic Usage

```ruby
# Check and auto-ingest if stale
result = Candles::FreshnessChecker.ensure_fresh(
  timeframe: "1D",
  auto_ingest: true
)

# Just check without ingesting
result = Candles::FreshnessChecker.check_freshness(
  timeframe: "1D"
)

# Custom thresholds
result = Candles::FreshnessChecker.ensure_fresh(
  timeframe: "1D",
  max_age_days: 2,              # Allow up to 2 days old
  min_freshness_percentage: 90, # Require 90% fresh
  auto_ingest: true
)
```

### Result Format

```ruby
{
  fresh: true/false,
  total_count: 1000,
  fresh_count: 950,
  stale_count: 50,
  freshness_percentage: 95.0,
  cutoff_date: 2024-12-30,
  timeframe: "1D",
  ingested: true/false,           # Only if auto_ingest was true
  ingestion_result: {...}         # Only if ingested
}
```

## Integration Points

### Swing Screener

```ruby
# app/services/screeners/swing_screener.rb
def call
  # Automatically checks daily candles before screening
  Candles::FreshnessChecker.ensure_fresh(
    timeframe: "1D",
    auto_ingest: !Rails.env.test?
  )
  # ... rest of screening logic
end
```

### Longterm Screener

```ruby
# app/services/screeners/longterm_screener.rb
def call
  # Checks both daily and weekly candles
  Candles::FreshnessChecker.ensure_fresh(timeframe: "1D", ...)
  Candles::FreshnessChecker.ensure_fresh(timeframe: "1W", ...)
  # ... rest of screening logic
end
```

## Configuration

### Environment Variables

None required - uses sensible defaults.

### AlgoConfig (Optional)

Can be extended to add configuration:

```yaml
# config/algo.yml
candles:
  freshness:
    max_age_days: 1
    min_freshness_percentage: 80.0
    auto_ingest: true
```

## Server Startup

To ensure candles are fresh on server startup, add to your deployment process:

```bash
# In your deployment script or Procfile
rails candles:check_freshness
```

Or add to an initializer (not recommended for production - use cron/job instead):

```ruby
# config/initializers/candle_freshness.rb (optional)
if Rails.env.production? && !Rails.env.test?
  Rails.application.config.after_initialize do
    Thread.new do
      sleep 30 # Wait for server to be ready
      Candles::FreshnessChecker.ensure_fresh(timeframe: "1D")
      Candles::FreshnessChecker.ensure_fresh(timeframe: "1W")
    end
  end
end
```

## Best Practices

1. **Screener Level**: Auto-ingest at screener level (handles bulk operations)
2. **Analysis Level**: Only check, don't auto-ingest (avoids blocking individual analysis)
3. **Tests**: Disable auto-ingest in tests to avoid side effects
4. **Monitoring**: Monitor freshness percentage in logs/alerts
5. **Cron Jobs**: Use scheduled jobs for regular freshness checks

## Monitoring

The system logs freshness status:

```
[Candles::FreshnessChecker] Candles are fresh: 950/1000 instruments (95.0%)
[Candles::FreshnessChecker] Candles are stale (75.0% fresh). Triggering ingestion...
[Screeners::SwingScreener] Starting with stale candles: 75.0% fresh. Ingestion triggered.
```

## Troubleshooting

### Candles Always Stale

- Check if ingestion jobs are running
- Verify API connectivity
- Check for rate limiting issues
- Review ingestion logs

### Auto-Ingestion Not Triggering

- Check `auto_ingest` parameter (disabled in tests)
- Verify ingestion services are available
- Check for errors in freshness checker logs

### Performance Concerns

- Freshness check queries all instruments (can be slow with large universe)
- Consider caching freshness status for short periods
- Use background jobs for ingestion to avoid blocking
