# System Quick Reference

**Quick answers to common questions**

---

## What Does `bin/dev` Start?

**Starts:**
- ✅ Rails web server (port 3000)
- ✅ JavaScript watcher (auto-compile)
- ✅ CSS watcher (auto-compile)

**Does NOT Start:**
- ❌ SolidQueue worker (needs separate process)
- ❌ Scheduled jobs (need SolidQueue worker)

**To Enable Full Automation:**
```bash
# Terminal 1
bin/dev

# Terminal 2
bin/rails solid_queue:start
```

---

## Three Modes Explained

### 🟢 Live Trading
- **Real money** → Places orders via DhanHQ
- **Real positions** → Tracks in `orders` table
- **Real balance** → From DhanHQ API
- **Use:** Production trading

### 📘 Paper Trading
- **Virtual money** → Uses `PaperPortfolio`
- **Virtual positions** → Tracks in `paper_positions` table
- **Virtual balance** → Calculated from portfolio
- **Use:** Practice, testing, validation

### 🎯 Simulation
- **No money** → Just calculates P&L
- **No positions** → Just stores results
- **Historical data** → Uses past candles
- **Use:** Analyze missed opportunities

---

## Portfolio Management

### Live Trading
- **No separate portfolio** → Uses DhanHQ as source of truth
- **Balance:** From DhanHQ API
- **Positions:** Synced from DhanHQ (if API supports)

### Paper Trading
- **Portfolio:** `PaperPortfolio` model
- **Balance:** `capital - reserved_capital = available_capital`
- **Positions:** `PaperPosition` records
- **P&L:** Calculated from entry/exit prices

### Simulation
- **No portfolio** → Just calculates per-signal P&L

---

## Balance Calculation

### Live Trading
```ruby
Dhan::Balance.check_available_balance
# Returns balance from DhanHQ API
```

### Paper Trading
```ruby
portfolio.available_capital = capital - reserved_capital
portfolio.total_equity = capital + unrealized_pnl
```

### Simulation
- Not used (shows what was needed at signal time)

---

## Position Tracking

### Live Trading
- **Orders Table:** All orders stored
- **Status:** pending → placed → executed
- **Exit:** Exit orders placed when SL/TP hit

### Paper Trading
- **PaperPositions Table:** All positions stored
- **Status:** open → closed
- **Exit:** Positions closed when SL/TP hit
- **Price Updates:** From daily candles

### Simulation
- **No positions** → Just calculates exit price and P&L

---

## Performance Calculation

### Live Trading
- P&L from actual order execution
- Entry/exit prices from DhanHQ

### Paper Trading
```ruby
# Unrealized (open)
pnl = (current_price - entry_price) × quantity

# Realized (closed)
pnl = (exit_price - entry_price) × quantity

# Portfolio
total_equity = capital + unrealized_pnl
```

### Simulation
```ruby
simulated_pnl = (exit_price - entry_price) × quantity
# Stored in trading_signals table
```

---

## Notifications

**Sent For:**
- ✅ Trading recommendations (insufficient balance)
- ✅ Entry (order placed / position created)
- ✅ Exit (order placed / position closed)
- ✅ Errors
- ✅ Daily summary (paper trading)
- ✅ Health checks

**Not Sent For:**
- ❌ Simulations (manual analysis only)

---

## Automation Checklist

**With `bin/dev` + SolidQueue Worker:**

- ✅ Daily candle ingestion (07:30 IST)
- ✅ Weekly candle ingestion (07:30 IST Monday)
- ✅ Swing screener (07:40 IST weekdays)
- ✅ Signal generation (after screening)
- ✅ Entry monitoring (every 30 min, market hours)
- ✅ Exit monitoring (every 30 min, market hours)
- ✅ Health monitoring (every 30 min, market hours)
- ✅ Balance checking (before each trade)
- ✅ Risk limit enforcement
- ✅ Notifications (all events)

---

## What's NOT Automated

- ❌ Partial exits (exits full position)
- ❌ Position scaling (no adding to positions)
- ❌ DhanHQ position syncing (would need API)
- ❌ Real-time prices (uses daily candles)
- ❌ Simulation (manual trigger)

---

## Quick Commands

```bash
# Start everything
bin/dev                    # Web server + watchers
bin/rails solid_queue:start  # Background jobs

# Simulate signals
rails trading_signals:simulate_all
rails trading_signals:simulate[123]

# Analyze performance
rails trading_signals:analyze
rails metrics:daily

# Check status
rails console
> TradingSignal.count
> PaperPortfolio.first.available_capital
> Order.count
```

---

## Mode Selection Guide

**Use Live Trading When:**
- ✅ You have sufficient capital
- ✅ Strategy is validated
- ✅ Ready for real trading
- ✅ Have risk management in place

**Use Paper Trading When:**
- ✅ Testing new strategies
- ✅ Learning the system
- ✅ Validating before going live
- ✅ Practicing without risk

**Use Simulation When:**
- ✅ Analyzing missed opportunities
- ✅ Understanding what-if scenarios
- ✅ Planning capital needs
- ✅ Validating strategy performance

---

## Key Files

- `config/recurring.yml` - Job schedules
- `config/algo.yml` - Trading configuration
- `app/models/trading_signal.rb` - Signal tracking
- `app/models/paper_portfolio.rb` - Paper portfolio
- `app/models/order.rb` - Live orders
- `app/services/strategies/swing/executor.rb` - Trade execution
- `app/services/paper_trading/executor.rb` - Paper execution
- `app/services/trading_signals/simulator.rb` - Simulation

---

**For complete details, see [Complete System Guide](COMPLETE_SYSTEM_GUIDE.md)**
