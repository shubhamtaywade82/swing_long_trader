# Paper Trading Wiring Verification

## ✅ Integration Points Verified

### 1. Configuration
- ✅ `config/application.rb` - Paper trading config added
- ✅ Environment variable: `PAPER_TRADING=true` enables paper mode
- ✅ Environment variable: `PAPER_TRADING_CAPITAL` sets initial capital

### 2. Signal Execution Flow

**Entry Point**: `Strategies::Swing::Executor.call(signal)`

**Flow**:
```
Strategies::Swing::Executor.call(signal)
  ↓
validate_signal()
  ↓
Paper Trading Enabled?
  ├─ YES → place_entry_order() → execute_paper_trade()
  │                                  ↓
  │                          PaperTrading::Executor.execute()
  │                                  ↓
  │                          PaperTrading::RiskManager.check_limits()
  │                                  ↓
  │                          PaperTrading::Position.create()
  │                                  ↓
  │                          Returns { success: true, position: ..., paper_trade: true }
  │
  └─ NO  → check_risk_limits() (live trading checks)
            ↓
            check_circuit_breaker() (live trading checks)
            ↓
            check_manual_approval_required() (live trading checks)
            ↓
            place_entry_order() → Dhan::Orders.place_order()
            ↓
            Returns { success: true, order: ..., paper_trade: false }
```

### 3. Paper Trading Mode Checks

✅ **Skipped in Paper Mode**:
- `check_risk_limits()` - Returns success immediately (paper trading has its own risk manager)
- `check_circuit_breaker()` - Returns success immediately (no circuit breaker for paper)
- `check_manual_approval_required()` - Returns success immediately (no approval needed for paper)

✅ **Paper Trading Risk Management**:
- Handled by `PaperTrading::RiskManager.check_limits()`
- Uses paper portfolio capital, not live capital
- Checks paper positions, not live orders

### 4. Capital Management

**Paper Trading**:
- Entry: Reserve capital (increment `reserved_capital`), capital stays same
- Exit: Release reserved capital, add/subtract P&L to capital
- Equity = capital + unrealized P&L

**Live Trading**:
- Uses `Setting.fetch_i('portfolio.current_capital')` for capital
- Orders placed via Dhan API

### 5. Result Handling

**Paper Trading Result**:
```ruby
{
  success: true,
  position: PaperPosition,
  paper_trade: true,
  message: "Paper trade executed: ..."
}
```

**Live Trading Result**:
```ruby
{
  success: true,
  order: Order,
  paper_trade: false,
  dhan_response: {...}
}
```

### 6. Logging

✅ **Logging Updated**:
- `log_order_placement()` now shows "PAPER", "DRY RUN", or "LIVE" mode
- `ExecutorJob` logs mode correctly
- Paper trades send their own Telegram notifications

### 7. Job Integration

✅ **ExecutorJob**:
- Handles both paper and live trading results
- Skips duplicate Telegram notifications for paper trades (they send their own)
- Logs mode correctly

### 8. Exit Monitoring

**Paper Trading Exits**:
- `PaperTrading::ExitMonitorJob` - Checks paper positions
- `PaperTrading::Simulator.check_exits()` - Monitors SL/TP/time-based exits
- Updates prices from `CandleSeriesRecord`

**Live Trading Exits**:
- `Strategies::Swing::ExitMonitorJob` - Checks live orders
- Uses Dhan API for order placement

### 9. Daily Reconciliation

**Paper Trading**:
- `PaperTrading::ReconciliationJob` - Updates paper positions
- `PaperTrading::Reconciler.call()` - Mark-to-market updates
- Sends daily summary via Telegram

**Live Trading**:
- Uses broker API for position updates

## 🔍 Verification Checklist

- [x] Paper trading mode check in executor
- [x] Paper trading executor properly called
- [x] Live trading checks skipped in paper mode
- [x] Risk management uses correct capital source
- [x] Result format consistent for both modes
- [x] Logging shows correct mode
- [x] Telegram notifications work for both modes
- [x] Capital management logic correct
- [x] Exit monitoring separate for paper/live
- [x] Daily reconciliation separate for paper/live

## 🧪 Testing Scenarios

### Scenario 1: Paper Trading Enabled
```ruby
ENV['PAPER_TRADING'] = 'true'
signal = { instrument_id: 1, direction: :long, entry_price: 100, qty: 10, sl: 95, tp: 110 }
result = Strategies::Swing::Executor.call(signal)
# Expected: { success: true, position: PaperPosition, paper_trade: true }
```

### Scenario 2: Live Trading (Paper Disabled)
```ruby
ENV['PAPER_TRADING'] = 'false'
signal = { instrument_id: 1, direction: :long, entry_price: 100, qty: 10, sl: 95, tp: 110 }
result = Strategies::Swing::Executor.call(signal)
# Expected: { success: true, order: Order, paper_trade: false }
```

### Scenario 3: Dry Run Mode
```ruby
ENV['DRY_RUN'] = 'true'
ENV['PAPER_TRADING'] = 'false'
signal = { instrument_id: 1, direction: :long, entry_price: 100, qty: 10, sl: 95, tp: 110 }
result = Strategies::Swing::Executor.call(signal, dry_run: true)
# Expected: { success: true, order: Order (dry_run: true), paper_trade: false }
```

## ✅ All Systems Wired Correctly

The paper trading module is fully integrated and will:
1. ✅ Route signals to paper trading when `PAPER_TRADING=true`
2. ✅ Route signals to live trading when `PAPER_TRADING=false`
3. ✅ Skip live trading checks in paper mode
4. ✅ Use paper portfolio for risk management in paper mode
5. ✅ Handle results correctly in both modes
6. ✅ Log and notify correctly for both modes
