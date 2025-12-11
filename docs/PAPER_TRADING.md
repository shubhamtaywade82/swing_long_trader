# Paper Trading Module

## Overview

The Paper Trading module provides a complete simulation environment for testing swing trading strategies without risking real capital. It simulates all aspects of live trading including capital management, position tracking, P&L calculation, exit conditions, and portfolio reconciliation.

## Features

- **Full Capital Simulation**: Tracks capital, reserved capital, available capital, and total equity
- **Position Management**: Creates and manages paper positions with entry/exit tracking
- **P&L Tracking**: Real-time realized and unrealized P&L calculation
- **Exit Conditions**: Automatic detection of SL/TP hits, time-based exits
- **Risk Management**: Enforces position size limits, exposure limits, drawdown limits
- **Daily Reconciliation**: Mark-to-market updates after market close
- **Telegram Notifications**: Real-time alerts for entries, exits, and daily summaries
- **Ledger System**: Complete audit trail of all transactions

## Architecture

### Database Tables

- `paper_portfolios`: Portfolio-level data (capital, equity, P&L)
- `paper_positions`: Individual positions (entry/exit prices, status, P&L)
- `paper_ledgers`: Transaction ledger (credits/debits, reasons)

### Services

- `PaperTrading::Portfolio`: Portfolio creation and management
- `PaperTrading::Position`: Position creation and management
- `PaperTrading::Ledger`: Transaction recording
- `PaperTrading::Executor`: Signal execution (creates positions)
- `PaperTrading::Simulator`: Exit condition checking
- `PaperTrading::Reconciler`: Daily mark-to-market
- `PaperTrading::RiskManager`: Risk limit enforcement

### Jobs

- `PaperTrading::ExitMonitorJob`: Periodic exit condition checking (every 30 min - 1 hour)
- `PaperTrading::ReconciliationJob`: Daily mark-to-market (after market close)

## Configuration

### Environment Variables

```bash
# Enable paper trading mode
PAPER_TRADING=true

# Set initial capital (default: 100000)
PAPER_TRADING_CAPITAL=100000
```

### Application Configuration

Paper trading is configured in `config/application.rb`:

```ruby
config.x.paper_trading.enabled = ENV["PAPER_TRADING"] == "true"
config.x.paper_trading.initial_capital = (ENV["PAPER_TRADING_CAPITAL"] || 100_000).to_f
```

## Usage

### Initialization

```bash
# Initialize paper trading portfolio with default capital (₹100,000)
rails paper_trading:init

# Initialize with custom capital
rails paper_trading:init[500000]
```

### Execution Flow

When paper trading is enabled, the `Strategies::Swing::Executor` automatically routes signals to `PaperTrading::Executor` instead of placing live orders via Dhan API.

```ruby
# Signal execution automatically uses paper trading if enabled
signal = {
  instrument_id: 123,
  direction: :long,
  entry_price: 4080,
  sl: 3985,
  tp: 4500,
  qty: 35
}

Strategies::Swing::Executor.call(signal)
# → Routes to PaperTrading::Executor if PAPER_TRADING=true
# → Routes to Dhan::Orders if PAPER_TRADING=false
```

### Monitoring

```bash
# Check exit conditions for open positions
rails paper_trading:check_exits

# Perform daily mark-to-market reconciliation
rails paper_trading:reconcile

# View portfolio summary
rails paper_trading:summary

# View ledger entries
rails paper_trading:ledger
```

### Scheduled Jobs

Set up cron jobs or use SolidQueue to schedule:

```ruby
# Every 30 minutes during market hours
PaperTrading::ExitMonitorJob.perform_later

# Daily after market close (e.g., 4:00 PM IST)
PaperTrading::ReconciliationJob.perform_later
```

## Risk Management

The paper trading module enforces the same risk limits as live trading:

- **Max Position Size**: Default 10% of capital per position
- **Max Total Exposure**: Default 50% of capital
- **Max Open Positions**: Default 5 positions
- **Daily Loss Limit**: Default 5% of capital
- **Max Drawdown**: Default 20% from peak equity

Configure these in `config/algo.yml`:

```yaml
risk:
  max_position_size_pct: 10.0
  max_total_exposure_pct: 50.0
  max_open_positions: 5
  max_daily_loss_pct: 5.0
  max_drawdown_pct: 20.0
```

## Exit Conditions

Positions are automatically exited when:

1. **Stop Loss Hit**: Price reaches SL level
2. **Take Profit Hit**: Price reaches TP level
3. **Time-Based Exit**: Max holding days reached (default: 20 days)
4. **Manual Exit**: Via API or rake task (future)

## Telegram Notifications

The module sends Telegram notifications for:

- **Entry**: When a new paper position is created
- **Exit**: When a position is closed (with P&L)
- **Daily Summary**: Portfolio snapshot after reconciliation
- **Alerts**: Risk limit breaches, errors

## Example Workflow

```bash
# 1. Enable paper trading
export PAPER_TRADING=true
export PAPER_TRADING_CAPITAL=100000

# 2. Initialize portfolio
rails paper_trading:init

# 3. Run swing trading system (signals will be executed as paper trades)
# Your existing swing trading pipeline will automatically use paper trading

# 4. Monitor exits (run periodically)
rails paper_trading:check_exits

# 5. Daily reconciliation (after market close)
rails paper_trading:reconcile

# 6. View summary
rails paper_trading:summary
```

## Integration with Existing System

The paper trading module integrates seamlessly with your existing swing trading pipeline:

```
Daily Ingestion → Screener → AI Ranking → Signal Generation → Executor
                                                                    ↓
                                                          Paper Trading Mode?
                                                                    ↓
                                                    ┌───────────────┴───────────────┐
                                                    ↓                               ↓
                                        PaperTrading::Executor          Dhan::Orders
                                                    ↓                               ↓
                                            Paper Position                    Live Order
```

## Benefits

1. **Zero Risk**: Test strategies without risking real capital
2. **Real-Time Simulation**: Uses actual market data for price updates
3. **Complete Tracking**: Full audit trail of all trades
4. **Risk Validation**: Test risk management rules before going live
5. **Performance Analysis**: Compare paper vs live performance
6. **Confidence Building**: Validate system before enabling auto-execution

## Future Enhancements

- [ ] Manual position exit via API
- [ ] Portfolio rebalancing
- [ ] Long-term investment allocation routing
- [ ] AI-based rebalancing summaries
- [ ] Performance comparison dashboard
- [ ] Multi-portfolio support
