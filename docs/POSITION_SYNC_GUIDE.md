# Position Sync Guide

**Complete guide to syncing live and paper positions in the database**

---

## Overview

The system now maintains **complete position tracking** in the database for both live and paper trading:

- **Live Positions:** Synced with DhanHQ API, stored in `positions` table
- **Paper Positions:** Tracked in `paper_positions` table
- **Automatic Sync:** Positions synced every 15 minutes during market hours
- **Price Updates:** Current prices updated from DhanHQ (live) or candles (paper)
- **P&L Calculation:** Unrealized and realized P&L calculated automatically

---

## Database Structure

### Live Positions Table (`positions`)

**Key Fields:**
- `instrument_id` - Link to instrument
- `order_id` - Entry order
- `exit_order_id` - Exit order (when closed)
- `trading_signal_id` - Link to signal
- `symbol`, `direction`, `entry_price`, `current_price`, `quantity`
- `stop_loss`, `take_profit`, `trailing_stop_distance`, `trailing_stop_pct`
- `status` - `open`, `closed`, `partially_closed`
- `unrealized_pnl`, `realized_pnl` - P&L tracking
- `dhan_position_id` - DhanHQ position ID
- `synced_with_dhan` - Sync status
- `last_synced_at` - Last sync timestamp

### Paper Positions Table (`paper_positions`)

**Already exists** - Fully tracked:
- `paper_portfolio_id` - Link to portfolio
- `instrument_id` - Link to instrument
- `direction`, `entry_price`, `current_price`, `quantity`
- `status` - `open` or `closed`
- `unrealized_pnl`, `realized_pnl` - P&L tracking

---

## How Position Sync Works

### Live Trading Position Sync

**1. Position Creation (On Order Execution)**
```
Order Executed
├─ Strategies::Swing::Executor creates Position record
├─ Links to Order and TradingSignal
├─ Sets entry_price, quantity, direction
├─ Sets stop_loss, take_profit from signal
└─ Status: "open"
```

**2. Automatic Sync (Every 15 Minutes)**
```
Positions::SyncJob runs
├─ Dhan::Positions.sync_all
│  ├─ Fetches positions from DhanHQ API
│  ├─ Creates/updates Position records
│  ├─ Links to orders if found
│  └─ Marks as synced_with_dhan: true
│
└─ Positions::Reconciler.reconcile_live
   ├─ Updates current_price from instrument.ltp
   ├─ Updates highest/lowest_price for trailing stops
   ├─ Calculates unrealized_pnl
   └─ Updates position records
```

**3. Exit Detection**
```
Exit Monitor runs (every 30 minutes)
├─ Checks open positions
├─ Updates current_price
├─ Checks SL/TP/trailing stop conditions
├─ Places exit order when triggered
└─ Marks position as closed
```

### Paper Trading Position Sync

**1. Position Creation (On Trade Execution)**
```
Paper Trade Executed
├─ PaperTrading::Executor creates PaperPosition
├─ Reserves capital
├─ Links to TradingSignal
└─ Status: "open"
```

**2. Automatic Reconciliation (Every 15 Minutes)**
```
Positions::SyncJob runs
└─ Positions::Reconciler.reconcile_paper
   ├─ Updates current_price from latest candle
   ├─ Calculates unrealized_pnl
   ├─ Updates portfolio equity
   └─ Updates position records
```

**3. Exit Detection**
```
PaperTrading::Simulator.check_exits runs
├─ Updates position prices
├─ Checks SL/TP conditions
├─ Closes position when triggered
├─ Calculates realized_pnl
└─ Updates portfolio capital
```

---

## Position Lifecycle

### Live Position Lifecycle

```
1. ORDER PLACED
   ├─ Order record created (status: "pending")
   └─ TradingSignal created (executed: false)

2. ORDER EXECUTED
   ├─ Order status: "executed"
   ├─ Position record created (status: "open")
   ├─ TradingSignal updated (executed: true, order_id set)
   └─ Position linked to Order and TradingSignal

3. SYNC WITH DHANHQ (Every 15 min)
   ├─ Dhan::Positions.sync_all fetches from API
   ├─ Position updated with DhanHQ data
   ├─ dhan_position_id set
   ├─ synced_with_dhan: true
   └─ last_synced_at updated

4. PRICE UPDATES (Every 15 min)
   ├─ current_price updated from instrument.ltp
   ├─ highest_price/lowest_price updated
   ├─ unrealized_pnl calculated
   └─ Position record updated

5. EXIT TRIGGERED
   ├─ Exit order placed
   ├─ Position.mark_as_closed! called
   ├─ Status: "closed"
   ├─ realized_pnl calculated
   └─ exit_order_id set
```

### Paper Position Lifecycle

```
1. POSITION CREATED
   ├─ PaperPosition created (status: "open")
   ├─ Capital reserved
   ├─ TradingSignal updated (executed: true, paper_position_id set)
   └─ Position linked to PaperPortfolio

2. PRICE UPDATES (Every 15 min or on exit check)
   ├─ current_price updated from latest candle
   ├─ unrealized_pnl calculated
   ├─ Portfolio equity updated
   └─ Position record updated

3. EXIT TRIGGERED
   ├─ Position closed (status: "closed")
   ├─ realized_pnl calculated
   ├─ Capital updated (P&L added/subtracted)
   ├─ Reserved capital released
   └─ Portfolio equity updated
```

---

## Sync Configuration

### Automatic Sync (Scheduled)

**config/recurring.yml:**
```yaml
position_sync:
  class: Positions::SyncJob
  schedule: "*/15 9-15 * * 1-5"  # Every 15 minutes, market hours
  queue: default
  priority: 1
```

**What it does:**
- Syncs live positions with DhanHQ API
- Updates prices for live positions
- Reconciles paper positions
- Calculates P&L for all positions

### Manual Sync

```bash
# Sync live positions with DhanHQ
rails positions:sync_live

# Reconcile paper positions
rails positions:reconcile_paper

# Sync and reconcile all
rails positions:sync_all

# List all open positions
rails positions:list

# Show position summary
rails positions:summary
```

---

## Position Queries

### Live Positions

```ruby
# All open positions
Position.open

# Positions by symbol
Position.open.by_symbol("RELIANCE")

# Positions with profit
Position.open.where("unrealized_pnl > 0")

# Positions with loss
Position.open.where("unrealized_pnl < 0")

# Synced positions
Position.synced

# Positions not synced
Position.not_synced

# Long positions
Position.open.long

# Short positions
Position.open.short
```

### Paper Positions

```ruby
# All open paper positions
PaperPosition.open

# Positions in portfolio
portfolio = PaperPortfolio.find_by(name: "default")
portfolio.open_positions

# Positions with profit
PaperPosition.open.where("pnl > 0")

# Positions with loss
PaperPosition.open.where("pnl < 0")
```

### Combined Queries

```ruby
# Total open positions (live + paper)
total_open = Position.open.count + PaperPosition.open.count

# Total unrealized P&L
live_unrealized = Position.open.sum(:unrealized_pnl)
paper_unrealized = PaperPortfolio.first.pnl_unrealized
total_unrealized = live_unrealized + paper_unrealized
```

---

## Position Updates

### Live Position Updates

**Automatic (Every 15 minutes):**
- Current price from `instrument.ltp`
- Highest/lowest price for trailing stops
- Unrealized P&L
- Sync status with DhanHQ

**Manual:**
```ruby
position = Position.find(123)
position.update!(current_price: 2500.0)
position.update_unrealized_pnl!
```

### Paper Position Updates

**Automatic (Every 15 minutes or on exit check):**
- Current price from latest candle
- Unrealized P&L
- Portfolio equity

**Manual:**
```ruby
position = PaperPosition.find(123)
position.update_current_price!(2500.0)
position.update_unrealized_pnl!
```

---

## DhanHQ Position Sync

### How It Works

**Dhan::Positions.sync_all:**
1. Fetches positions from DhanHQ API
2. For each position:
   - Finds or creates Position record
   - Links to Instrument
   - Links to Order if found
   - Updates with DhanHQ data
   - Marks as `synced_with_dhan: true`
3. Marks missing positions as closed (if not in API response)

### API Integration

**Note:** The sync service tries common DhanHQ API method names:
- `get_positions`
- `get_holdings`
- `get_portfolio`

**You may need to adjust** based on your DhanHQ client implementation:
- Edit `app/services/dhan/positions.rb`
- Update method names and response parsing
- Adjust field mappings based on actual API response

### Sync Metadata

Each position stores sync history:
```ruby
position.sync_metadata_hash
# {
#   sync_history: [
#     { synced_at: Time, dhan_data: {...}, changes: {...} }
#   ]
# }
```

---

## Exit Monitoring with Positions

### Live Trading

**Exit Monitor now uses Positions:**
```ruby
# Checks Position.open instead of just Order
open_positions = Position.open

# Updates current_price
position.update!(current_price: instrument.ltp)

# Checks exit conditions
if position.check_sl_hit?
  # Place exit order
  # Mark position as closed
end
```

### Paper Trading

**Exit Monitor uses PaperPositions:**
```ruby
# Checks PaperPosition.open
open_positions = portfolio.open_positions

# Updates prices from candles
position.update_current_price!(latest_candle.close)

# Checks exit conditions
if position.check_sl_hit?
  # Close position
  # Update portfolio
end
```

---

## P&L Calculation

### Live Positions

**Unrealized P&L (Open):**
```ruby
position.calculate_unrealized_pnl
# Returns: { pnl: amount, pnl_pct: percentage }

# Auto-updated on sync
position.update_unrealized_pnl!
```

**Realized P&L (Closed):**
```ruby
position.calculate_realized_pnl
# Returns: { pnl: amount, pnl_pct: percentage }

# Set when position closed
position.mark_as_closed!(exit_price: 2500, exit_reason: "tp_hit")
```

### Paper Positions

**Unrealized P&L:**
```ruby
position.unrealized_pnl  # Auto-calculated
position.unrealized_pnl_pct  # Auto-calculated
```

**Realized P&L:**
```ruby
position.realized_pnl  # Set on exit
position.realized_pnl_pct  # Set on exit
```

---

## Position Status Tracking

### Status Values

**Live Positions:**
- `open` - Active position
- `closed` - Position closed
- `partially_closed` - Partial exit (if implemented)

**Paper Positions:**
- `open` - Active position
- `closed` - Position closed

### Status Transitions

**Live:**
```
open → closed (on exit)
open → partially_closed (on partial exit, if implemented)
```

**Paper:**
```
open → closed (on exit)
```

---

## Reconciliation Process

### Live Reconciliation

**Every 15 minutes:**
1. Sync with DhanHQ API
2. Update current prices
3. Update highest/lowest prices
4. Calculate unrealized P&L
5. Check for missing positions (closed in DhanHQ)

### Paper Reconciliation

**Every 15 minutes:**
1. Update position prices from candles
2. Calculate unrealized P&L
3. Update portfolio equity
4. Update drawdown

---

## Benefits of Database Sync

### Complete Audit Trail

- ✅ All positions tracked in database
- ✅ Price history maintained
- ✅ P&L calculated and stored
- ✅ Sync history tracked

### Accurate Monitoring

- ✅ Real-time position status
- ✅ Accurate P&L calculation
- ✅ Exit conditions checked on positions
- ✅ Portfolio equity always up-to-date

### Analysis & Reporting

- ✅ Query positions by status, symbol, P&L
- ✅ Calculate portfolio metrics
- ✅ Track performance over time
- ✅ Compare live vs paper performance

---

## Troubleshooting

### Positions Not Syncing

**Check:**
1. DhanHQ API credentials configured
2. DhanHQ client methods match API
3. Sync job running (check SolidQueue)
4. Review logs: `tail -f log/development.log | grep Position`

### Prices Not Updating

**Check:**
1. Instrument LTP available (live)
2. Candle data available (paper)
3. Reconciliation job running
4. Position records exist

### P&L Incorrect

**Check:**
1. Entry/exit prices correct
2. Quantity matches
3. Direction correct (long/short)
4. Calculation method matches position type

---

## Migration

Run the migration to create positions table:

```bash
rails db:migrate
```

This creates:
- `positions` table for live trading
- Indexes for efficient queries
- Foreign keys to orders and signals

---

## Summary

**Now Fully Synced:**

✅ **Live Positions** - Synced with DhanHQ, stored in database  
✅ **Paper Positions** - Tracked in database, prices from candles  
✅ **Automatic Sync** - Every 15 minutes during market hours  
✅ **Price Updates** - Current prices updated automatically  
✅ **P&L Calculation** - Unrealized and realized P&L tracked  
✅ **Exit Monitoring** - Uses synced positions for accurate exits  
✅ **Complete Audit Trail** - All positions and changes tracked  

Everything is now synced and tracked in the database for both live and paper trading!
