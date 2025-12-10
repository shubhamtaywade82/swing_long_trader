# 📁 SwingLongAlgoTrader File Mapping Reference

**Quick reference: What files to copy from AlgoScalperAPI to SwingLongTrader**

---

## ✅ Files to Copy (Exact Copy)

### Models

| Source (AlgoScalperAPI)                     | Destination (SwingLongTrader)               | Notes      |
| ------------------------------------------- | ------------------------------------------- | ---------- |
| `app/models/instrument.rb`                  | `app/models/instrument.rb`                  | Exact copy |
| `app/models/candle_series.rb`               | `app/models/candle_series.rb`               | Exact copy |
| `app/models/candle.rb`                      | `app/models/candle.rb`                      | Exact copy |
| `app/models/concerns/candle_extension.rb`   | `app/models/concerns/candle_extension.rb`   | Exact copy |
| `app/models/concerns/instrument_helpers.rb` | `app/models/concerns/instrument_helpers.rb` | Exact copy |

### Indicators (Entire Directory)

| Source                                                | Destination                                           | Notes              |
| ----------------------------------------------------- | ----------------------------------------------------- | ------------------ |
| `app/services/indicators/base_indicator.rb`           | `app/services/indicators/base_indicator.rb`           | Exact copy         |
| `app/services/indicators/calculator.rb`               | `app/services/indicators/calculator.rb`               | Exact copy         |
| `app/services/indicators/indicator_factory.rb`        | `app/services/indicators/indicator_factory.rb`        | Exact copy         |
| `app/services/indicators/threshold_config.rb`         | `app/services/indicators/threshold_config.rb`         | Exact copy         |
| `app/services/indicators/supertrend_indicator.rb`     | `app/services/indicators/supertrend_indicator.rb`     | Exact copy         |
| `app/services/indicators/supertrend.rb`               | `app/services/indicators/supertrend.rb`               | Exact copy         |
| `app/services/indicators/adx_indicator.rb`            | `app/services/indicators/adx_indicator.rb`            | Exact copy         |
| `app/services/indicators/rsi_indicator.rb`            | `app/services/indicators/rsi_indicator.rb`            | Exact copy         |
| `app/services/indicators/macd_indicator.rb`           | `app/services/indicators/macd_indicator.rb`           | Exact copy         |
| `app/services/indicators/trend_duration_indicator.rb` | `app/services/indicators/trend_duration_indicator.rb` | Exact copy         |
| `app/services/indicators/holy_grail.rb`               | `app/services/indicators/holy_grail.rb`               | Optional - if used |

### Providers

| Source                                          | Destination                                     | Notes      |
| ----------------------------------------------- | ----------------------------------------------- | ---------- |
| `lib/providers/dhanhq_provider.rb`              | `lib/providers/dhanhq_provider.rb`              | Exact copy |
| `app/services/concerns/dhanhq_error_handler.rb` | `app/services/concerns/dhanhq_error_handler.rb` | Exact copy |

### Notifications

| Source                                     | Destination                                | Notes                                       |
| ------------------------------------------ | ------------------------------------------ | ------------------------------------------- |
| `lib/telegram_notifier.rb`                 | `lib/telegram_notifier.rb`                 | Or `lib/notifications/telegram_notifier.rb` |
| `lib/notifications/telegram_notifier.rb`   | `lib/notifications/telegram_notifier.rb`   | If exists                                   |
| `config/initializers/telegram_notifier.rb` | `config/initializers/telegram_notifier.rb` | Exact copy                                  |

### Base Services

| Source                                | Destination                           | Notes      |
| ------------------------------------- | ------------------------------------- | ---------- |
| `app/services/application_service.rb` | `app/services/application_service.rb` | Exact copy |

### Data Import & Setup

| Source                                  | Destination                             | Notes                                           |
| --------------------------------------- | --------------------------------------- | ----------------------------------------------- |
| `app/services/instruments_importer.rb`  | `app/services/instruments_importer.rb`  | **CRITICAL** - Modify for stocks-only if needed |
| `app/models/setting.rb`                 | `app/models/setting.rb`                 | **NEW** - Required for importer statistics      |
| `app/models/instrument_type_mapping.rb` | `app/models/instrument_type_mapping.rb` | **NEW** - Used by importer                      |
| `lib/tasks/instruments.rake`            | `lib/tasks/instruments.rake`            | **CRITICAL** - Import tasks                     |
| `db/seeds.rb`                           | `db/seeds.rb`                           | **HEAVILY MODIFY** - Remove scalper watchlist   |

### Configuration

| Source                                 | Destination                            | Notes                                                        |
| -------------------------------------- | -------------------------------------- | ------------------------------------------------------------ |
| `config/initializers/algo_config.rb`   | `config/initializers/algo_config.rb`   | Exact copy                                                   |
| `config/initializers/dhanhq_config.rb` | `config/initializers/dhanhq_config.rb` | Exact copy                                                   |
| `config/algo.yml`                      | `config/algo.yml`                      | **HEAVILY MODIFY** - Remove scalper config, add swing config |

### Database Migrations

| Source                                              | Destination                                         | Notes                                                |
| --------------------------------------------------- | --------------------------------------------------- | ---------------------------------------------------- |
| `db/migrate/YYYYMMDDHHMMSS_create_instruments.rb`   | `db/migrate/YYYYMMDDHHMMSS_create_instruments.rb`   | Copy structure, regenerate timestamp                 |
| `db/migrate/YYYYMMDDHHMMSS_create_candle_series.rb` | `db/migrate/YYYYMMDDHHMMSS_create_candle_series.rb` | Copy structure, regenerate timestamp (or create new) |

---

## ⚠️ Files to Copy with Modifications

### Configuration Files

| Source                  | Destination             | Modifications Required                                          |
| ----------------------- | ----------------------- | --------------------------------------------------------------- |
| `config/algo.yml`       | `config/algo.yml`       | Remove all scalper config, add swing/long-term config           |
| `config/application.rb` | `config/application.rb` | Change `queue_adapter` to `:solid_queue`, remove Sidekiq config |
| `config/database.yml`   | `config/database.yml`   | Update database name to `swing_long_trader_*`                   |

### Gemfile

| Source    | Destination | Modifications Required                                                     |
| --------- | ----------- | -------------------------------------------------------------------------- |
| `Gemfile` | `Gemfile`   | Remove `sidekiq`, `redis` (if not needed), ensure `solid_queue` is present |

---

## ❌ Files NOT to Copy (Scalper-Specific)

### Services - DO NOT COPY

| Source                                       | Reason                                                     |
| -------------------------------------------- | ---------------------------------------------------------- |
| `app/services/live/` (entire directory)      | WebSocket, MarketFeedHub, ActiveCache - scalper-specific   |
| `app/services/entries/` (entire directory)   | Scalper entry logic                                        |
| `app/services/orders/` (entire directory)    | BracketPlacer, scalper order logic                         |
| `app/services/positions/` (entire directory) | Position tracking for scalping                             |
| `app/services/risk/` (entire directory)      | ExitEngine, TrailingEngine, RiskManager - scalper-specific |
| `app/services/signal/` (entire directory)    | Signal::Scheduler, scalper signals                         |
| `app/services/trading/` (entire directory)   | Trading supervisor, scalper logic                          |
| `app/services/tick_cache.rb`                 | Tick-level caching - scalper-specific                      |
| `app/services/trading_session.rb`            | Intraday session management - scalper-specific             |
| `app/services/index_config_loader.rb`        | If scalper-specific                                        |
| `app/services/index_instrument_cache.rb`     | If scalper-specific                                        |

### Models - DO NOT COPY

| Source                                | Reason                                                        |
| ------------------------------------- | ------------------------------------------------------------- |
| `app/models/position_tracker.rb`      | Scalper position tracking                                     |
| `app/models/derivative.rb`            | **OPTIONAL** - Only copy if trading options/futures for swing |
| `app/models/trading_signal.rb`        | If scalper-specific                                           |
| `app/models/watchlist_item.rb`        | Scalper-specific watchlist                                    |
| `app/models/best_indicator_params.rb` | If scalper-optimized                                          |

### Initializers - DO NOT COPY

| Source                                      | Reason                                    |
| ------------------------------------------- | ----------------------------------------- |
| `config/initializers/market_stream.rb`      | WebSocket initialization                  |
| `config/initializers/trading_supervisor.rb` | Scalper supervisor                        |
| `config/initializers/orders_gateway.rb`     | If scalper-specific                       |
| `config/initializers/sidekiq.rb`            | Sidekiq config (using SolidQueue instead) |

### Jobs - DO NOT COPY

| Source                     | Reason              |
| -------------------------- | ------------------- |
| `app/jobs/*_signal_job.rb` | Scalper signal jobs |
| `app/jobs/*_entry_job.rb`  | Scalper entry jobs  |
| `app/jobs/*_exit_job.rb`   | Scalper exit jobs   |
| `app/jobs/*_risk_job.rb`   | Scalper risk jobs   |

**Note:** Create NEW jobs for swing trading (see migration guide)

---

## 🆕 Files to Create (New for Swing Trading)

### New Services

| New File                                         | Purpose                                       |
| ------------------------------------------------ | --------------------------------------------- |
| `app/services/candles/daily_ingestor.rb`         | Fetch and store daily candles                 |
| `app/services/candles/weekly_ingestor.rb`        | Fetch and store weekly candles                |
| `app/services/candles/intraday_fetcher.rb`       | Fetch intraday candles on-demand (no storage) |
| `app/services/screeners/swing_screener.rb`       | Screen instruments for swing opportunities    |
| `app/services/screeners/ai_ranker.rb`            | Rank candidates using AI                      |
| `app/services/screeners/final_selector.rb`       | Final selection from ranked candidates        |
| `app/services/strategies/swing/engine.rb`        | Swing strategy engine                         |
| `app/services/strategies/swing/evaluator.rb`     | Evaluate swing signals                        |
| `app/services/strategies/swing/notifier.rb`      | Send swing notifications                      |
| `app/services/strategies/swing/executor.rb`      | Execute swing trades                          |
| `app/services/strategies/long_term/engine.rb`    | Long-term strategy engine                     |
| `app/services/strategies/long_term/evaluator.rb` | Evaluate long-term signals                    |

### New Jobs

| New File                                         | Purpose                         |
| ------------------------------------------------ | ------------------------------- |
| `app/jobs/candles/daily_ingestor_job.rb`         | Daily candle ingestion job      |
| `app/jobs/candles/weekly_ingestor_job.rb`        | Weekly candle ingestion job     |
| `app/jobs/candles/intraday_fetcher_job.rb`       | Intraday candle fetching job    |
| `app/jobs/screeners/swing_screener_job.rb`       | Swing screener job              |
| `app/jobs/screeners/ai_ranker_job.rb`            | AI ranking job                  |
| `app/jobs/strategies/swing_analysis_job.rb`      | Swing analysis job              |
| `app/jobs/strategies/swing_entry_monitor_job.rb` | Monitor for swing entry signals |
| `app/jobs/strategies/swing_exit_monitor_job.rb`  | Monitor for swing exit signals  |

### New Configuration

| New File               | Purpose                            |
| ---------------------- | ---------------------------------- |
| `config/recurring.yml` | SolidQueue recurring job schedules |

### New Controllers (Optional - for API)

| New File                                       | Purpose                 |
| ---------------------------------------------- | ----------------------- |
| `app/controllers/api/health_controller.rb`     | Health check endpoint   |
| `app/controllers/api/screeners_controller.rb`  | Screener API (optional) |
| `app/controllers/api/strategies_controller.rb` | Strategy API (optional) |

---

## 📋 Copy Commands Reference

### Quick Copy Script (Bash)

```bash
#!/bin/bash
# Copy script for migration
# Usage: ./copy_files.sh /path/to/algo_scalper_api /path/to/swing_long_trader

SOURCE=$1
DEST=$2

# Models
cp "$SOURCE/app/models/instrument.rb" "$DEST/app/models/"
cp "$SOURCE/app/models/candle_series.rb" "$DEST/app/models/"
cp "$SOURCE/app/models/candle.rb" "$DEST/app/models/"
cp -r "$SOURCE/app/models/concerns/"* "$DEST/app/models/concerns/"

# Indicators
cp -r "$SOURCE/app/services/indicators/"* "$DEST/app/services/indicators/"

# Providers
mkdir -p "$DEST/lib/providers"
cp "$SOURCE/lib/providers/dhanhq_provider.rb" "$DEST/lib/providers/"

# Notifications
mkdir -p "$DEST/lib/notifications"
cp "$SOURCE/lib/telegram_notifier.rb" "$DEST/lib/" 2>/dev/null || true
cp "$SOURCE/lib/notifications/telegram_notifier.rb" "$DEST/lib/notifications/" 2>/dev/null || true

# Base services
cp "$SOURCE/app/services/application_service.rb" "$DEST/app/services/"

# Concerns
mkdir -p "$DEST/app/services/concerns"
cp "$SOURCE/app/services/concerns/dhanhq_error_handler.rb" "$DEST/app/services/concerns/"

# Config
cp "$SOURCE/config/initializers/algo_config.rb" "$DEST/config/initializers/"
cp "$SOURCE/config/initializers/dhanhq_config.rb" "$DEST/config/initializers/"
cp "$SOURCE/config/initializers/telegram_notifier.rb" "$DEST/config/initializers/" 2>/dev/null || true

echo "Files copied. Remember to:"
echo "1. Modify config/algo.yml for swing trading"
echo "2. Update config/application.rb for SolidQueue"
echo "3. Create new migrations for instruments and candle_series"
echo "4. Create new swing-specific services and jobs"
```

---

## 🔍 Verification After Copy

### Check for Scalper References

After copying, search for these patterns to ensure no scalper code leaked:

```bash
# Search for scalper-specific terms
grep -r "scalper\|Scalper" app/ lib/ config/
grep -r "MarketFeedHub\|ActiveCache" app/ lib/
grep -r "BracketPlacer\|ExitEngine\|TrailingEngine" app/
grep -r "PositionTracker\|position_tracker" app/models/
grep -r "WebSocket\|websocket" app/ config/
grep -r "tick_cache\|TickCache" app/
grep -r "Sidekiq\|sidekiq" config/
```

### Verify Required Files Exist

```bash
# Check models
test -f app/models/instrument.rb && echo "✓ instrument.rb"
test -f app/models/candle_series.rb && echo "✓ candle_series.rb"
test -f app/models/candle.rb && echo "✓ candle.rb"

# Check indicators
test -f app/services/indicators/base_indicator.rb && echo "✓ base_indicator.rb"
test -f app/services/indicators/supertrend_indicator.rb && echo "✓ supertrend_indicator.rb"

# Check providers
test -f lib/providers/dhanhq_provider.rb && echo "✓ dhanhq_provider.rb"

# Check config
test -f config/initializers/algo_config.rb && echo "✓ algo_config.rb"
test -f config/initializers/dhanhq_config.rb && echo "✓ dhanhq_config.rb"
```

---

## 📝 Notes

1. **Always regenerate migration timestamps** when copying migrations
2. **Review and modify** `config/algo.yml` - don't copy scalper config
3. **Update database names** in `config/database.yml`
4. **Remove Sidekiq references** - use SolidQueue instead
5. **Test each copied file** loads without errors
6. **Search for hardcoded references** to scalper-specific services

---

**Last Updated:** Based on AlgoScalperAPI codebase analysis

