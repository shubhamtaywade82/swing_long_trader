# How the Application Works

**Understanding the automated screening and trading flow**

---

## Important: Rails Server Alone Doesn't Trade!

**Starting `rails server` only starts the web application.** It does **NOT** automatically:
- Run screeners
- Generate trading signals
- Place trades
- Monitor positions

**You need to also start SolidQueue workers** to process background jobs.

---

## The Complete System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Rails Application                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Web Server │  │  Background  │  │   Scheduled   │     │
│  │   (Puma)     │  │   Jobs       │  │    Jobs       │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         SolidQueue Worker (REQUIRED!)                │  │
│  │  Processes scheduled jobs from config/recurring.yml   │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## How It Actually Works

### Step 1: Start the System

You need **TWO processes running**:

**Terminal 1 - Rails Server:**
```bash
rails server
# or
bin/dev  # Starts web server + asset watchers
```

**Terminal 2 - SolidQueue Worker (REQUIRED for automation):**
```bash
bin/rails solid_queue:start
```

**Or use Foreman (recommended):**
```bash
# Edit Procfile.dev to include:
web: env RUBY_DEBUG_OPEN=true bin/rails server
js: yarn build --watch
css: yarn watch:css
jobs: bin/rails solid_queue:start

# Then run:
bin/dev
```

### Step 2: Scheduled Jobs Run Automatically

SolidQueue reads `config/recurring.yml` and schedules jobs:

```yaml
production:
  # Daily candle ingestion - 07:30 IST daily
  daily_candle_ingestion:
    class: Candles::DailyIngestorJob
    schedule: "30 7 * * *"  # Cron format

  # Swing screener - 07:40 IST weekdays
  swing_screener:
    class: Screeners::SwingScreenerJob
    schedule: "40 7 * * 1-5"  # Monday-Friday

  # Monitor job - Every 30 minutes during market hours
  monitor_job:
    class: MonitorJob
    schedule: "*/30 9-15 * * 1-5"  # 9 AM - 3:30 PM IST
```

**What happens:**
1. SolidQueue checks the schedule every minute
2. When scheduled time arrives, it enqueues the job
3. Worker picks up the job and executes it
4. Results are logged and notifications sent

---

## Complete Flow: From Screening to Trading

### Flow 1: Daily Screening (Automatic)

```
07:30 IST - Daily Candle Ingestion
├─ Candles::DailyIngestorJob runs
├─ Fetches latest daily candles from DhanHQ API
└─ Stores in database

07:40 IST - Swing Screener
├─ Screeners::SwingScreenerJob runs
├─ Analyzes all instruments in universe
├─ Calculates indicators (EMA, RSI, ADX, MACD, Supertrend)
├─ Scores each instrument (0-100)
├─ Selects top candidates
├─ Sends top 10 to Telegram (if configured)
└─ Optionally triggers AnalysisJob for top 20

[If auto_analyze enabled]
├─ Strategies::Swing::AnalysisJob runs
├─ Evaluates top candidates for entry signals
├─ Generates trading signals
└─ Sends signal alerts to Telegram
```

### Flow 2: Signal Execution (Manual or Automatic)

**Option A: Manual Execution (Default for First 30 Trades)**

```
Signal Generated
├─ Strategies::Swing::Executor called
├─ Checks: Is this trade #1-30? → YES
├─ Creates Order with requires_approval: true
├─ Sends Telegram approval request
└─ Waits for manual approval

[You approve via Telegram or Rails console]
├─ Orders::ProcessApprovedJob runs
├─ Places order via DhanHQ API
└─ Sends confirmation notification
```

**Option B: Automatic Execution (After 30 Trades)**

```
Signal Generated
├─ Strategies::Swing::Executor called
├─ Checks: Is this trade #1-30? → NO
├─ Checks risk limits (position size, total exposure)
├─ Checks circuit breaker (failure rate)
├─ Places order via DhanHQ API
└─ Sends notification
```

### Flow 3: Position Monitoring (If Enabled)

```
[Entry Monitor - Every 30 minutes during market hours]
├─ Strategies::Swing::EntryMonitorJob runs
├─ Checks top candidates for entry conditions
├─ Generates signals
└─ Executes via Executor (if conditions met)

[Exit Monitor - Every 30 minutes during market hours]
├─ Strategies::Swing::ExitMonitorJob runs
├─ Checks open positions for exit conditions
│  ├─ Take profit hit?
│  ├─ Stop loss hit?
│  └─ Trailing stop triggered?
└─ Places exit orders if conditions met
```

---

## Configuration: What Runs Automatically?

### Current Default Configuration

**Automatic (Scheduled):**
- ✅ Daily candle ingestion (07:30 IST daily)
- ✅ Weekly candle ingestion (07:30 IST Monday)
- ✅ Swing screener (07:40 IST weekdays)
- ✅ Health monitoring (Every 30 min, 9 AM - 3:30 PM IST)
- ✅ Job queue cleanup (Every hour)

**Manual/On-Demand:**
- ⚠️ Signal analysis (triggered by screener if `auto_analyze: true`)
- ⚠️ Trade execution (requires approval for first 30 trades)
- ⚠️ Entry monitoring (commented out in `config/recurring.yml`)
- ⚠️ Exit monitoring (commented out in `config/recurring.yml`)

### Enable Full Automation

To enable automatic trading, edit `config/recurring.yml`:

```yaml
production:
  # Uncomment these for automatic entry/exit monitoring:
  swing_entry_monitor:
    class: Strategies::Swing::EntryMonitorJob
    schedule: "*/30 9-15 * * 1-5"  # Every 30 min, 9 AM - 3:30 PM IST
    queue: default
    priority: 1

  swing_exit_monitor:
    class: Strategies::Swing::ExitMonitorJob
    schedule: "*/30 9-15 * * 1-5"  # Every 30 min, 9 AM - 3:30 PM IST
    queue: default
    priority: 1
```

And edit `config/algo.yml`:

```yaml
swing_trading:
  strategy:
    auto_analyze: true  # Enable automatic analysis after screening
```

**⚠️ WARNING:** Only enable automatic trading after:
1. Testing in dry-run mode
2. Validating first 30 trades manually
3. Understanding risk management settings
4. Having proper monitoring in place

---

## Dry-Run Mode (Recommended for Testing)

Enable dry-run mode to test without placing real orders:

```bash
# Set environment variable
export DRY_RUN=true

# Or in config/algo.yml (if supported)
# execution:
#   dry_run: true
```

**What dry-run does:**
- ✅ Runs all screeners
- ✅ Generates signals
- ✅ Calculates risk checks
- ✅ Logs what would be executed
- ❌ Does NOT place real orders
- ❌ Does NOT deduct capital

---

## Paper Trading Mode (Alternative to Dry-Run)

Enable paper trading to simulate real trading with virtual capital:

```yaml
# config/algo.yml
paper_trading:
  enabled: true
  initial_balance: 100000  # Starting balance in rupees
  simulate_slippage: true
  slippage_pct: 0.1
```

**What paper trading does:**
- ✅ Places "virtual" orders
- ✅ Tracks positions and P&L
- ✅ Simulates slippage and execution
- ✅ Stores results in database
- ❌ Does NOT place real orders
- ❌ Does NOT use real capital

---

## Manual Execution (Current Default)

### Run Screener Manually

```bash
# Run swing screener
rails screener:swing

# Or via Rails runner
rails runner "Screeners::SwingScreenerJob.perform_now"
```

### Generate Signals Manually

```bash
# Run analysis for specific instruments
rails runner "
  candidate_ids = [1, 2, 3]  # Instrument IDs
  Strategies::Swing::AnalysisJob.perform_now(candidate_ids)
"
```

### Execute Trades Manually

```bash
# Approve pending orders
rails orders:approve[123]  # Order ID

# Or via Rails console
rails console
> order = Order.find(123)
> order.approve!
> Orders::ProcessApprovedJob.perform_now(order_id: 123)
```

---

## Understanding the Job Schedule

### Cron Format Explanation

```
"30 7 * * *"     → 07:30 IST every day
"40 7 * * 1-5"   → 07:40 IST Monday-Friday
"*/30 9-15 * * 1-5" → Every 30 minutes, 9 AM - 3:30 PM IST, weekdays
```

**Format:** `minute hour day month weekday`
- `*` = every
- `*/30` = every 30 units
- `1-5` = Monday to Friday
- `9-15` = 9 AM to 3:30 PM (hour range)

**Note:** Times are in **server timezone** (usually UTC). Adjust for IST (UTC+5:30).

### IST Timezone Example

```yaml
# 07:30 IST = 02:00 UTC (in winter) or 01:30 UTC (in summer)
daily_candle_ingestion:
  schedule: "0 2 * * *"  # 07:30 IST (adjust for DST)
```

---

## What Happens When You Start Rails Server?

### With Only Rails Server Running:

```
✅ Web application accessible at http://localhost:3000
✅ Can run manual commands (rails console, rake tasks)
✅ Can trigger jobs manually
❌ Scheduled jobs DO NOT run automatically
❌ No automatic screening
❌ No automatic trading
```

### With Rails Server + SolidQueue Worker:

```
✅ Web application accessible
✅ Scheduled jobs run automatically
✅ Screeners run at scheduled times
✅ Monitoring jobs run periodically
✅ Can still run manual commands
⚠️ Trading depends on configuration (manual approval vs automatic)
```

---

## Complete Example: Typical Day

### Morning (Before Market Opens)

```
07:30 IST - Daily Candle Ingestion
├─ Fetches yesterday's candle data
└─ Updates database

07:40 IST - Swing Screener
├─ Analyzes 500+ instruments
├─ Finds 25 candidates with score > 70
├─ Sends top 10 to Telegram
└─ Triggers AnalysisJob for top 20

07:45 IST - Analysis Job (if auto_analyze enabled)
├─ Evaluates 20 candidates
├─ Generates 5 trading signals
└─ Sends signal alerts to Telegram
```

### During Market Hours (9 AM - 3:30 PM IST)

```
Every 30 minutes - Monitor Job
├─ Checks system health
├─ Verifies API connectivity
└─ Alerts if issues detected

[If Entry Monitor enabled]
Every 30 minutes - Entry Monitor
├─ Checks top candidates for entry
├─ Generates signals if conditions met
└─ Executes orders (if approved/automatic)

[If Exit Monitor enabled]
Every 30 minutes - Exit Monitor
├─ Checks open positions
├─ Triggers exits if stop loss/take profit hit
└─ Places exit orders
```

### After Market Hours

```
Hourly - Job Queue Cleanup
├─ Removes old completed jobs
└─ Keeps database clean
```

---

## Troubleshooting: Jobs Not Running

### Check SolidQueue Status

```bash
# Check if worker is running
ps aux | grep solid_queue

# Check job queue status
rails console
> SolidQueue::Job.count
> SolidQueue::Job.pending.count
> SolidQueue::Job.failed.count

# View failed jobs
rails console
> SolidQueue::FailedExecution.last&.error_class
> SolidQueue::FailedExecution.last&.error_message
```

### Check Scheduled Jobs

```bash
# View recurring tasks
rails console
> SolidQueue::RecurringTask.all.each { |t| puts "#{t.task_key}: #{t.schedule}" }

# Manually trigger a job
rails runner "Screeners::SwingScreenerJob.perform_now"
```

### Common Issues

**Issue: Jobs scheduled but not running**
- ✅ Check SolidQueue worker is running: `bin/rails solid_queue:start`
- ✅ Check `config/recurring.yml` syntax is correct
- ✅ Check server timezone matches schedule expectations

**Issue: Jobs running but no results**
- ✅ Check logs: `tail -f log/development.log`
- ✅ Check API credentials in `.env`
- ✅ Check database has candle data: `rails candles:status`

**Issue: Trades not executing**
- ✅ Check if manual approval required (first 30 trades)
- ✅ Check risk limits in `config/algo.yml`
- ✅ Check if dry-run mode is enabled
- ✅ Check order status: `rails console` → `Order.last`

---

## Summary

### To Get Automatic Screening and Trading:

1. **Start Rails Server:**
   ```bash
   rails server
   ```

2. **Start SolidQueue Worker (REQUIRED):**
   ```bash
   bin/rails solid_queue:start
   ```

3. **Configure Automation (Optional):**
   - Edit `config/recurring.yml` to enable entry/exit monitors
   - Edit `config/algo.yml` to enable `auto_analyze: true`
   - Set `manual_approval.enabled: false` after 30 trades

4. **Monitor:**
   - Check logs: `tail -f log/development.log`
   - Check Telegram notifications
   - Check job status: `rails solid_queue:status`

### Current Default Behavior:

- ✅ **Automatic:** Candle ingestion, screening, health monitoring
- ⚠️ **Semi-Automatic:** Signal generation (if `auto_analyze: true`)
- ⚠️ **Manual:** Trade execution (first 30 trades require approval)
- ❌ **Disabled:** Entry/exit monitoring (commented out)

---

**Remember:** The Rails server alone is just a web application. You need SolidQueue workers running to process scheduled jobs and enable automation!
