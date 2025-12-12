# Complete System Guide

**Understanding Live Trading, Paper Trading, and Simulation Modes**

---

## Table of Contents

1. [System Modes Overview](#system-modes-overview)
2. [What Each Mode Does](#what-each-mode-does)
3. [Portfolio Management](#portfolio-management)
4. [Position Tracking & Syncing](#position-tracking--syncing)
5. [Balance Calculation](#balance-calculation)
6. [Performance Calculation](#performance-calculation)
7. [Notification System](#notification-system)
8. [Complete Automation Flow](#complete-automation-flow)
9. [What `bin/dev` Starts](#what-bindev-starts)
10. [Features & Capabilities](#features--capabilities)

---

## System Modes Overview

The system operates in **three distinct modes**:

### 1. **Live Trading Mode** 🟢
- **Real money** - Places actual orders via DhanHQ API
- **Real positions** - Tracks positions synced with DhanHQ
- **Real balance** - Uses your actual DhanHQ account balance
- **Real P&L** - Actual profit/loss from real trades

### 2. **Paper Trading Mode** 📘
- **Virtual money** - Simulates trading with virtual capital
- **Virtual positions** - Creates positions in database (not in DhanHQ)
- **Virtual balance** - Tracks portfolio balance separately
- **Simulated P&L** - Calculates profit/loss based on market prices

### 3. **Simulation Mode** 🎯
- **What-if analysis** - Simulates trades that weren't executed
- **Historical data** - Uses past candle data to calculate outcomes
- **No positions** - Doesn't create positions, just calculates P&L
- **Performance analysis** - Helps understand missed opportunities

---

## What Each Mode Does

### Live Trading Mode

**How it works:**
1. **Signal Generated** → Creates `TradingSignal` record
2. **Balance Checked** → Checks DhanHQ account balance
3. **Order Placed** → Places real order via DhanHQ API
4. **Order Tracked** → Stores `Order` record in database
5. **Position Synced** → Syncs with DhanHQ positions (if API supports)
6. **Exit Monitored** → Monitors for SL/TP hits
7. **Exit Executed** → Places real exit order when conditions met

**Database Storage:**
- `orders` table - All orders placed
- `trading_signals` table - All signals (executed and not executed)
- **No separate portfolio table** - Uses DhanHQ as source of truth

**Balance Source:**
- DhanHQ API - Real account balance
- Checked before each trade via `Dhan::Balance.check_available_balance`

**Position Tracking:**
- Orders stored in `orders` table
- Status: `pending`, `placed`, `executed`, `rejected`, `failed`
- Can sync with DhanHQ positions if API supports it
- Exit monitoring checks order status and current prices

### Paper Trading Mode

**How it works:**
1. **Signal Generated** → Creates `TradingSignal` record
2. **Balance Checked** → Checks `PaperPortfolio.available_capital`
3. **Position Created** → Creates `PaperPosition` record (virtual)
4. **Capital Reserved** → Reserves capital (doesn't debit)
5. **Price Updated** → Updates position prices from candles
6. **Exit Checked** → Checks SL/TP conditions
7. **Position Closed** → Closes position, calculates P&L, updates capital

**Database Storage:**
- `paper_portfolios` table - Virtual portfolios
- `paper_positions` table - Virtual positions (open/closed)
- `paper_ledgers` table - Audit trail of all transactions
- `trading_signals` table - All signals with execution status

**Balance Source:**
- `PaperPortfolio.capital` - Virtual capital
- `PaperPortfolio.available_capital` - Capital minus reserved
- `PaperPortfolio.total_equity` - Capital + unrealized P&L

**Position Tracking:**
- All positions stored in `paper_positions` table
- Status: `open` or `closed`
- Prices updated from `candle_series_records`
- Exit conditions checked by `PaperTrading::Simulator`

### Simulation Mode

**How it works:**
1. **Signal Not Executed** → Signal exists but `executed: false`
2. **Simulation Triggered** → Run `signal.simulate!` or `rails trading_signals:simulate_all`
3. **Historical Data Loaded** → Loads candles from signal date
4. **Exit Calculated** → Determines exit based on SL/TP/time
5. **P&L Calculated** → Calculates what P&L would have been
6. **Results Stored** → Stores in `trading_signals` table

**Database Storage:**
- `trading_signals` table - Stores simulation results
- **No positions created** - Just calculates and stores P&L

**Balance Source:**
- Not applicable - Simulation doesn't use balance
- Shows what balance was needed at time of signal

**Position Tracking:**
- **No positions** - Simulation doesn't create positions
- Just calculates exit price, P&L, holding days

---

## Portfolio Management

### Live Trading Portfolio

**Source of Truth:** DhanHQ Account

- **Balance:** Retrieved from DhanHQ API
- **Positions:** Synced from DhanHQ (if API supports)
- **Orders:** Stored in `orders` table
- **P&L:** Calculated from actual order execution

**No Separate Portfolio Table:**
- System doesn't maintain separate portfolio
- Uses DhanHQ as single source of truth
- Orders tracked for audit and monitoring

### Paper Trading Portfolio

**Source of Truth:** `paper_portfolios` Table

**Portfolio Structure:**
```ruby
PaperPortfolio:
  - capital: Initial + realized P&L
  - reserved_capital: Capital locked in open positions
  - available_capital: capital - reserved_capital
  - total_equity: capital + unrealized P&L
  - pnl_realized: Total realized profit/loss
  - pnl_unrealized: Total unrealized profit/loss
  - peak_equity: Highest equity reached
  - max_drawdown: Maximum drawdown percentage
```

**Capital Flow:**
1. **Initial Capital** → Set when portfolio created (default: ₹100,000)
2. **Entry** → Capital reserved (not debited), `reserved_capital` increases
3. **Exit** → P&L added/subtracted from `capital`, `reserved_capital` decreases
4. **Available Capital** → `capital - reserved_capital`

**Example:**
```
Initial: ₹100,000
Entry (₹10,000): capital=₹100,000, reserved=₹10,000, available=₹90,000
Exit (+₹2,000 profit): capital=₹102,000, reserved=₹0, available=₹102,000
```

### Simulation Portfolio

**No Portfolio:** Simulations don't use portfolios

- Just calculates P&L for individual signals
- Doesn't track portfolio balance
- Shows what would have happened per signal

---

## Position Tracking & Syncing

### Live Trading Positions

**Tracking Method:**
- **Orders Table** - All orders stored with status
- **Status Flow:** `pending` → `placed` → `executed` → (exit order)
- **DhanHQ Sync** - Can sync positions if API supports (not currently implemented)

**Current Implementation:**
- Orders tracked in `orders` table
- Exit monitoring checks order status
- No automatic position sync with DhanHQ (would need API support)

**Future Enhancement:**
- Could add `positions` table to sync with DhanHQ
- Would require DhanHQ API endpoint for positions
- Would sync periodically or on-demand

### Paper Trading Positions

**Tracking Method:**
- **PaperPositions Table** - All positions stored
- **Status:** `open` or `closed`
- **Price Updates:** From `candle_series_records` (daily candles)

**Position Lifecycle:**
1. **Created** → `PaperPosition` created with `status: "open"`
2. **Price Updated** → `current_price` updated from latest candle
3. **P&L Calculated** → `unrealized_pnl` calculated automatically
4. **Exit Checked** → `PaperTrading::Simulator.check_exits` runs
5. **Closed** → `status: "closed"`, `realized_pnl` calculated

**Price Update:**
- Uses latest daily candle from `candle_series_records`
- Updated during reconciliation or exit checks
- No real-time prices (uses end-of-day prices)

### Simulation Positions

**No Positions:** Simulations don't create positions

- Just calculates entry → exit → P&L
- Stores results in `trading_signals` table
- No position tracking needed

---

## Balance Calculation

### Live Trading Balance

**Source:** DhanHQ API

```ruby
# Check balance before trade
balance_result = Dhan::Balance.check_available_balance
available_balance = balance_result[:balance]
```

**Calculation:**
- Retrieved from DhanHQ API before each trade
- No local calculation - uses API as source of truth
- Checked in `Strategies::Swing::Executor.check_available_balance`

**Balance Fields in Signal:**
- `required_balance` - Amount needed for trade
- `available_balance` - Balance from DhanHQ API
- `balance_shortfall` - Difference (if insufficient)

### Paper Trading Balance

**Source:** `PaperPortfolio` Model

**Balance Components:**
```ruby
capital = initial_capital + realized_pnl
reserved_capital = sum of open positions entry values
available_capital = capital - reserved_capital
total_equity = capital + unrealized_pnl
```

**Calculation Flow:**
1. **Initial:** `capital = initial_capital` (e.g., ₹100,000)
2. **Entry:** `reserved_capital += entry_value`, `available_capital` decreases
3. **Exit:** `capital += pnl`, `reserved_capital -= entry_value`
4. **Equity:** `total_equity = capital + unrealized_pnl`

**Example:**
```
Initial: ₹100,000
Entry RELIANCE (₹10,000):
  capital: ₹100,000
  reserved: ₹10,000
  available: ₹90,000
  equity: ₹100,000 (no unrealized yet)

Price moves to ₹11,000:
  capital: ₹100,000
  reserved: ₹10,000
  unrealized_pnl: ₹1,000
  equity: ₹101,000

Exit at ₹11,000:
  capital: ₹101,000 (added ₹1,000 profit)
  reserved: ₹0
  available: ₹101,000
  equity: ₹101,000
```

### Simulation Balance

**Not Used:** Simulations don't calculate balance

- Shows what balance was needed at signal time
- Stored in `trading_signals.required_balance`
- Used for analysis, not execution

---

## Performance Calculation

### Live Trading Performance

**P&L Calculation:**
- From actual order execution prices
- Entry price: Order execution price
- Exit price: Exit order execution price
- P&L: (Exit - Entry) × Quantity (for long)

**Tracking:**
- Stored in `orders` table (if DhanHQ provides)
- Can calculate from order history
- No automatic P&L calculation (depends on DhanHQ API)

### Paper Trading Performance

**P&L Calculation:**

**Unrealized P&L (Open Positions):**
```ruby
position.unrealized_pnl = (current_price - entry_price) × quantity  # long
position.unrealized_pnl = (entry_price - current_price) × quantity  # short
```

**Realized P&L (Closed Positions):**
```ruby
position.realized_pnl = (exit_price - entry_price) × quantity  # long
position.realized_pnl = (entry_price - exit_price) × quantity  # short
```

**Portfolio Performance:**
```ruby
portfolio.pnl_realized = sum of all closed positions realized_pnl
portfolio.pnl_unrealized = sum of all open positions unrealized_pnl
portfolio.total_equity = capital + pnl_unrealized
portfolio.total_return_pct = ((total_equity - initial_capital) / initial_capital × 100)
```

**Metrics:**
- Win Rate: (Winning trades / Total trades) × 100
- Average P&L: Total P&L / Number of trades
- Max Drawdown: ((Peak Equity - Current Equity) / Peak Equity) × 100

### Simulation Performance

**P&L Calculation:**
```ruby
signal.simulated_pnl = (exit_price - entry_price) × quantity  # long
signal.simulated_pnl_pct = ((exit_price - entry_price) / entry_price) × 100
```

**Aggregate Metrics:**
- Total Simulated P&L: Sum of all `simulated_pnl`
- Win Rate: (Profitable signals / Total signals) × 100
- Average P&L: Total P&L / Number of signals

---

## Notification System

### Notification Types

**1. Trading Recommendations (Insufficient Balance)**
- Sent when signal generated but balance insufficient
- Includes: Full signal details + balance info + shortfall
- Context: "Trading Recommendation - Insufficient Balance"

**2. Entry Notifications**
- **Live:** Order placed successfully
- **Paper:** Position created successfully
- Includes: Symbol, direction, entry price, quantity, order/position ID

**3. Exit Notifications**
- **Live:** Exit order placed
- **Paper:** Position closed
- Includes: Symbol, exit reason, entry/exit prices, P&L, holding days

**4. Error Alerts**
- Order failures, API errors, system errors
- Includes: Error message, context, relevant details

**5. Daily Summary (Paper Trading)**
- Portfolio summary: Capital, equity, P&L, positions
- Sent by `PaperTrading::Reconciler`

**6. Health Monitoring**
- System health checks
- API connectivity, database, job queue status

### Notification Triggers

**Automatic:**
- ✅ Signal generated (if balance insufficient)
- ✅ Order placed (live)
- ✅ Position created (paper)
- ✅ Position closed (paper)
- ✅ Exit triggered (live/paper)
- ✅ Errors occurred
- ✅ Daily summary (paper)

**Manual:**
- Can trigger via Rails console or rake tasks

---

## Complete Automation Flow

### Daily Automation (Scheduled Jobs)

**07:30 IST - Daily Candle Ingestion**
```
Candles::DailyIngestorJob
├─ Fetches yesterday's candles from DhanHQ
├─ Stores in candle_series_records table
└─ Updates all instruments
```

**07:30 IST (Monday) - Weekly Candle Ingestion**
```
Candles::WeeklyIngestorJob
├─ Aggregates weekly candles from daily
├─ Stores in candle_series_records table
└─ Used for long-term analysis
```

**07:40 IST (Weekdays) - Swing Screener**
```
Screeners::SwingScreenerJob
├─ Analyzes all instruments in universe
├─ Calculates indicators (EMA, RSI, ADX, MACD, Supertrend)
├─ Scores each instrument (0-100)
├─ Selects top candidates
├─ Sends top 10 to Telegram
└─ Triggers AnalysisJob if auto_analyze enabled
```

**After Screening - Signal Analysis (if enabled)**
```
Strategies::Swing::AnalysisJob
├─ Evaluates top candidates
├─ Generates trading signals
├─ Creates TradingSignal records
├─ Sends signal alerts to Telegram
└─ Signals ready for execution
```

**Every 30 Minutes (9 AM - 3:30 PM IST, Weekdays) - Entry Monitor**
```
Strategies::Swing::EntryMonitorJob
├─ Checks top candidates for entry conditions
├─ Generates signals if conditions met
├─ Checks balance (paper or live)
├─ Executes trades automatically (if enabled)
└─ Sends notifications
```

**Every 30 Minutes (9 AM - 3:30 PM IST, Weekdays) - Exit Monitor**

**Live Trading:**
```
Strategies::Swing::ExitMonitorJob
├─ Checks open orders
├─ Checks SL/TP conditions
├─ Places exit orders when triggered
└─ Sends exit notifications
```

**Paper Trading:**
```
PaperTrading::Simulator.check_exits
├─ Updates position prices from candles
├─ Checks SL/TP conditions
├─ Closes positions when triggered
├─ Calculates P&L
├─ Updates portfolio capital
└─ Sends exit notifications
```

**Every 30 Minutes (9 AM - 3:30 PM IST, Weekdays) - Health Monitor**
```
MonitorJob
├─ Checks database connectivity
├─ Checks DhanHQ API connectivity
├─ Checks Telegram connectivity
├─ Checks candle freshness
├─ Checks job queue status
├─ Checks OpenAI costs
└─ Sends alerts if issues found
```

**Hourly - Job Queue Cleanup**
```
SolidQueue::Job.clear_finished_in_batches
├─ Removes old completed jobs
└─ Keeps database clean
```

### Manual Operations

**Simulation:**
```bash
rails trading_signals:simulate_all  # Simulate all not-executed signals
rails trading_signals:simulate[123]  # Simulate specific signal
```

**Analysis:**
```bash
rails trading_signals:analyze  # Performance analysis
rails metrics:daily  # Daily metrics
```

**Reconciliation (Paper Trading):**
```bash
rails runner "PaperTrading::Reconciler.call"  # Mark-to-market update
```

---

## What `bin/dev` Starts

### When You Run `bin/dev`

**Processes Started:**
1. **Rails Server** (Puma) - Web application on port 3000
2. **JavaScript Watcher** - Auto-compiles JS on changes
3. **CSS Watcher** - Auto-compiles CSS on changes

**What It Does NOT Start:**
- ❌ SolidQueue Worker (needs separate process)
- ❌ Scheduled jobs (need SolidQueue worker)

### To Enable Full Automation

**Terminal 1:**
```bash
bin/dev
# Starts: Rails server + JS watcher + CSS watcher
```

**Terminal 2:**
```bash
bin/rails solid_queue:start
# Starts: SolidQueue worker (processes scheduled jobs)
```

**Or Use Foreman (Recommended):**

Edit `Procfile.dev`:
```
web: env RUBY_DEBUG_OPEN=true bin/rails server
js: yarn build --watch
css: yarn watch:css
jobs: bin/rails solid_queue:start
```

Then run:
```bash
bin/dev
# Starts everything including SolidQueue worker
```

---

## Features & Capabilities

### Swing Trading

**✅ Implemented:**
- Daily screening with technical indicators
- Signal generation with entry/exit levels
- Risk-based position sizing
- Stop loss and take profit management
- Trailing stop support
- Entry/exit monitoring
- Automatic execution (paper and live)
- Balance checking
- Risk limit enforcement

**❌ Not Implemented:**
- Partial exits (exits full position)
- Position scaling (adds to position)
- Multiple timeframes analysis
- Custom exit strategies

### Long-Term Trading

**✅ Implemented:**
- Weekly screening
- Long-term signal generation
- Rebalancing logic (weekly/monthly)
- Minimum holding period
- Max positions limit
- Backtesting support

**❌ Not Implemented:**
- Live execution (only backtesting)
- Position monitoring (would need similar to swing)
- Automatic rebalancing (only in backtests)

### Position Sizing

**Current Implementation:**
- **Risk-Based:** 2% of capital per trade (configurable)
- **Max Position Size:** 10% per instrument (configurable)
- **Max Total Exposure:** 50% of capital (configurable)

**Formula:**
```ruby
risk_amount = capital × (risk_per_trade_pct / 100)
risk_per_share = entry_price - stop_loss
quantity = risk_amount / risk_per_share
```

**Not Implemented:**
- Kelly Criterion
- Volatility-based sizing
- Portfolio heat-based sizing
- Dynamic position sizing

### Partial Exits

**Current Status:** ❌ Not Implemented

**Current Behavior:**
- Exits full position when SL/TP hit
- No partial profit taking
- No scaling out

**Would Need:**
- Modify exit logic to support partial quantities
- Track partial exits in position records
- Update P&L calculation for partial exits

### Portfolio Sizing

**Current Implementation:**
- **Max Positions:** Configurable (default: 5 for paper, unlimited for live)
- **Max Exposure:** 50% of capital (configurable)
- **Position Limits:** Per instrument and total

**Not Implemented:**
- Dynamic portfolio sizing based on market conditions
- Correlation-based position limits
- Sector/industry limits

---

## Complete System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    RAILS APPLICATION                         │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              SOLIDQUEUE WORKER                        │  │
│  │  Processes scheduled jobs from config/recurring.yml  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   SCREENERS  │  │   ANALYZERS  │  │   EXECUTORS  │     │
│  │              │  │              │  │              │     │
│  │ - Swing      │  │ - Signal     │  │ - Live       │     │
│  │ - Long-term  │  │   Builder    │  │ - Paper      │     │
│  │ - AI Ranker  │  │ - Evaluator  │  │ - Simulator  │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   MONITORS   │  │   TRACKERS   │  │  NOTIFIERS   │     │
│  │              │  │              │  │              │     │
│  │ - Entry      │  │ - Positions  │  │ - Telegram   │     │
│  │ - Exit       │  │ - P&L        │  │ - Alerts     │     │
│  │ - Health     │  │ - Metrics    │  │ - Errors     │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      DATABASE                                │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   SIGNALS    │  │   ORDERS     │  │  POSITIONS   │     │
│  │              │  │              │  │              │     │
│  │ - All modes  │  │ - Live only  │  │ - Paper only │     │
│  │ - Execution  │  │ - DhanHQ     │  │ - Virtual    │     │
│  │   status     │  │   orders     │  │   positions  │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  PORTFOLIOS  │  │   CANDLES    │  │   METRICS    │     │
│  │              │  │              │  │              │     │
│  │ - Paper only │  │ - Historical │  │ - P&L        │     │
│  │ - Virtual    │  │ - Daily/Week  │  │ - Win rate   │     │
│  │   capital    │  │ - Indicators  │  │ - Drawdown   │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  EXTERNAL SERVICES                           │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   DHANHQ     │  │   TELEGRAM    │  │   OPENAI     │     │
│  │              │  │              │  │              │     │
│  │ - Orders     │  │ - Alerts     │  │ - AI Ranking │     │
│  │ - Balance    │  │ - Errors     │  │ - Analysis   │     │
│  │ - Prices     │  │ - Summary    │  │              │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

---

## Mode Comparison Table

| Feature | Live Trading | Paper Trading | Simulation |
|---------|--------------|---------------|------------|
| **Money** | Real | Virtual | None |
| **Orders** | Real (DhanHQ) | Virtual (DB) | None |
| **Positions** | DhanHQ (synced) | Virtual (DB) | None |
| **Balance** | DhanHQ API | PaperPortfolio | Not used |
| **P&L** | Real | Calculated | Calculated |
| **Execution** | Automatic | Automatic | Manual |
| **Notifications** | Yes | Yes | No |
| **Risk Limits** | Yes | Yes | N/A |
| **Exit Monitoring** | Yes | Yes | N/A |
| **Portfolio Tracking** | DhanHQ | PaperPortfolio | None |
| **Use Case** | Real trading | Practice/testing | Analysis |

---

## Understanding the Flow

### Complete Flow: Signal to Execution

```
1. SCREENING (07:40 IST)
   ├─ Screeners::SwingScreenerJob runs
   ├─ Analyzes instruments
   ├─ Finds candidates
   └─ Triggers AnalysisJob

2. SIGNAL GENERATION
   ├─ Strategies::Swing::AnalysisJob runs
   ├─ Evaluates candidates
   ├─ Generates signals
   ├─ Creates TradingSignal record (executed: false)
   └─ Sends Telegram alert

3. EXECUTION ATTEMPT (Every 30 min during market hours)
   ├─ Strategies::Swing::EntryMonitorJob runs
   ├─ Checks entry conditions
   ├─ Generates signals
   ├─ Strategies::Swing::Executor called
   │  ├─ Creates/updates TradingSignal record
   │  ├─ Checks balance
   │  ├─ Checks risk limits
   │  └─ Executes trade
   │
   ├─ LIVE MODE:
   │  ├─ Checks DhanHQ balance
   │  ├─ Places order via DhanHQ API
   │  ├─ Creates Order record
   │  ├─ Updates TradingSignal (executed: true, order_id set)
   │  └─ Sends entry notification
   │
   └─ PAPER MODE:
      ├─ Checks PaperPortfolio balance
      ├─ Creates PaperPosition record
      ├─ Reserves capital
      ├─ Updates TradingSignal (executed: true, paper_position_id set)
      └─ Sends entry notification

4. EXIT MONITORING (Every 30 min during market hours)
   ├─ LIVE MODE:
   │  ├─ Strategies::Swing::ExitMonitorJob runs
   │  ├─ Checks open orders
   │  ├─ Checks SL/TP conditions
   │  ├─ Places exit order when triggered
   │  └─ Sends exit notification
   │
   └─ PAPER MODE:
      ├─ PaperTrading::Simulator.check_exits runs
      ├─ Updates position prices from candles
      ├─ Checks SL/TP conditions
      ├─ Closes position when triggered
      ├─ Calculates P&L
      ├─ Updates portfolio capital
      └─ Sends exit notification

5. SIMULATION (Manual or Scheduled)
   ├─ TradingSignals::Simulator.simulate_all runs
   ├─ Finds not-executed signals
   ├─ Loads historical candles
   ├─ Simulates entry → exit
   ├─ Calculates P&L
   └─ Updates TradingSignal (simulated: true, simulated_pnl set)
```

---

## Key Differences Summary

### Live vs Paper Trading

| Aspect | Live | Paper |
|--------|------|-------|
| **Capital** | Real DhanHQ account | Virtual portfolio |
| **Orders** | Real orders placed | Virtual positions created |
| **Balance Check** | DhanHQ API | PaperPortfolio.available_capital |
| **Position Tracking** | Orders table | PaperPositions table |
| **P&L** | From actual execution | Calculated from prices |
| **Risk** | Real money at risk | No real risk |
| **Use Case** | Production trading | Testing/validation |

### Paper vs Simulation

| Aspect | Paper | Simulation |
|--------|-------|------------|
| **Positions** | Creates positions | No positions |
| **Capital** | Uses portfolio capital | Not used |
| **Execution** | Executes trades | Just calculates |
| **Real-time** | Updates with new prices | Uses historical data |
| **Use Case** | Practice trading | Analyze missed opportunities |

---

## Starting the System

### Development Mode

```bash
# Terminal 1: Start web server + watchers
bin/dev

# Terminal 2: Start background jobs
bin/rails solid_queue:start
```

### Production Mode

```bash
# Start Rails server (via systemd, supervisor, etc.)
rails server -e production

# Start SolidQueue worker (via systemd, supervisor, etc.)
bin/rails solid_queue:start
```

### What Runs Automatically

**With SolidQueue Worker Running:**
- ✅ Daily candle ingestion (07:30 IST)
- ✅ Weekly candle ingestion (07:30 IST Monday)
- ✅ Swing screener (07:40 IST weekdays)
- ✅ Signal analysis (after screening, if enabled)
- ✅ Entry monitoring (every 30 min, market hours)
- ✅ Exit monitoring (every 30 min, market hours)
- ✅ Health monitoring (every 30 min, market hours)
- ✅ Job queue cleanup (hourly)

**Without SolidQueue Worker:**
- ❌ No scheduled jobs run
- ❌ No automatic screening
- ❌ No automatic trading
- ✅ Web server works
- ✅ Manual commands work

---

## Configuration

### Enable Paper Trading

**Option 1: Environment Variable**
```bash
export PAPER_TRADING=true
export PAPER_TRADING_CAPITAL=100000
```

**Option 2: config/algo.yml**
```yaml
paper_trading:
  enabled: true
  initial_balance: 100000
```

### Enable Automatic Trading

**config/algo.yml**
```yaml
execution:
  auto_trading:
    enabled: true

swing_trading:
  strategy:
    auto_analyze: true
```

### Enable Entry/Exit Monitoring

**config/recurring.yml** (already enabled)
```yaml
swing_entry_monitor:
  class: Strategies::Swing::EntryMonitorJob
  schedule: "*/30 9-15 * * 1-5"

swing_exit_monitor:
  class: Strategies::Swing::ExitMonitorJob
  schedule: "*/30 9-15 * * 1-5"
```

---

## Summary

### What the System Can Do

**✅ Fully Automated:**
- Data ingestion (daily/weekly candles)
- Screening (swing and long-term)
- Signal generation
- AI-powered ranking
- Automatic trading (paper and live)
- Entry/exit monitoring
- Risk management
- Balance checking
- Notifications

**✅ Manual Operations:**
- Simulation of not-executed signals
- Performance analysis
- Backtesting
- Manual trade execution

**❌ Not Yet Implemented:**
- Partial exits
- Position scaling
- DhanHQ position syncing (would need API support)
- Real-time price updates (uses daily candles)
- Multiple portfolio management

### Mode Selection

- **Live Trading:** Real money, real orders, production use
- **Paper Trading:** Virtual money, practice, testing, validation
- **Simulation:** Analysis, what-if scenarios, performance understanding

All three modes work together to give you complete visibility into your trading system's performance!
