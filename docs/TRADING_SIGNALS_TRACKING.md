# Trading Signals Tracking

**Complete guide to tracking all trading recommendations in the database**

---

## Overview

All trading signals/recommendations are now **persisted in the database** with execution status, whether they were executed or not. This allows you to:

- Track all trading recommendations
- Analyze which signals were executed vs not executed
- Understand why signals weren't executed (insufficient balance, risk limits, etc.)
- Review historical recommendations
- Link signals to executed orders (live) or positions (paper)

---

## Database Model

### TradingSignal Model

**Table:** `trading_signals`

**Key Fields:**
- Signal details: `symbol`, `direction`, `entry_price`, `stop_loss`, `take_profit`, `quantity`, `confidence`, `risk_reward_ratio`
- Execution tracking: `executed`, `execution_type`, `execution_status`, `execution_reason`
- Links: `order_id` (live trading), `paper_position_id` (paper trading)
- Balance info: `required_balance`, `available_balance`, `balance_shortfall`
- Source: `source`, `screener_type`

---

## Execution Status

### Status Values

1. **`executed: true`** - Signal was successfully executed
   - `execution_type`: `"paper"` or `"live"`
   - `execution_status`: `"executed"`
   - Linked to `order` (live) or `paper_position` (paper)

2. **`executed: false`** - Signal was not executed
   - `execution_status`: `"not_executed"`, `"pending_approval"`, or `"failed"`
   - `execution_reason`: Why it wasn't executed
   - `execution_error`: Error message if failed

### Common Execution Reasons

- `"Insufficient balance"` - Not enough funds
- `"Order exceeds max position size"` - Risk limit exceeded
- `"Total exposure exceeds limit"` - Portfolio limit exceeded
- `"Manual approval required"` - Waiting for approval
- `"Circuit breaker activated"` - Too many failures
- `"Successfully executed"` - Executed successfully

---

## Usage Examples

### Query Executed Signals

```ruby
# All executed signals
TradingSignal.executed

# Executed in paper trading
TradingSignal.executed.paper

# Executed in live trading
TradingSignal.executed.live

# Recent executed signals
TradingSignal.executed.recent.limit(10)
```

### Query Not Executed Signals

```ruby
# All not executed signals
TradingSignal.not_executed

# Signals not executed due to insufficient balance
TradingSignal.not_executed.where("execution_reason LIKE ?", "%Insufficient%")

# Signals pending approval
TradingSignal.pending_approval

# Failed signals
TradingSignal.failed
```

### Query by Symbol

```ruby
# All signals for a symbol
TradingSignal.by_symbol("RELIANCE")

# Executed signals for a symbol
TradingSignal.by_symbol("RELIANCE").executed

# Not executed signals for a symbol
TradingSignal.by_symbol("RELIANCE").not_executed
```

### Query by Balance Issues

```ruby
# Signals with insufficient balance
TradingSignal.not_executed.where("balance_shortfall > 0")

# Signals where balance was checked
TradingSignal.where.not(available_balance: nil)

# Signals with large shortfall (> ₹10,000)
TradingSignal.where("balance_shortfall > ?", 10_000)
```

### Analyze Signal Performance

```ruby
# Success rate
total = TradingSignal.count
executed = TradingSignal.executed.count
success_rate = (executed.to_f / total * 100).round(2)

# Reasons for not executing
TradingSignal.not_executed.group(:execution_reason).count

# Average confidence of executed vs not executed
executed_avg_confidence = TradingSignal.executed.average(:confidence)
not_executed_avg_confidence = TradingSignal.not_executed.average(:confidence)

# Balance shortfall statistics
TradingSignal.where("balance_shortfall > 0").average(:balance_shortfall)
```

---

## Signal Creation Flow

### 1. Signal Generation (AnalysisJob)

When `AnalysisJob` generates signals:

```ruby
# Signal record created with:
- executed: false
- execution_status: nil (not attempted yet)
- source: "analysis_job"
- Balance info captured at generation time
```

### 2. Execution Attempt (Executor)

When `Executor` attempts to execute:

```ruby
# Signal record updated with:
- execution_attempted_at: Time.current
- Balance info updated if changed
```

### 3. Execution Result

**If Successful:**
```ruby
# Signal record updated with:
- executed: true
- execution_type: "paper" or "live"
- execution_status: "executed"
- order_id or paper_position_id set
- execution_completed_at: Time.current
```

**If Failed:**
```ruby
# Signal record updated with:
- executed: false
- execution_status: "not_executed" or "failed"
- execution_reason: "Insufficient balance" or other reason
- execution_error: Error message
```

---

## Integration Points

### Paper Trading

**When position is created:**
- Signal record is found or created
- Marked as `executed: true`, `execution_type: "paper"`
- Linked to `paper_position`

**When balance insufficient:**
- Signal record created/updated
- Marked as `executed: false`, `execution_status: "not_executed"`
- `execution_reason`: "Insufficient capital"
- Balance info stored

### Live Trading

**When order is placed:**
- Signal record is created before execution attempt
- If successful, marked as `executed: true`, `execution_type: "live"`
- Linked to `order`

**When balance insufficient:**
- Signal record created/updated
- Marked as `executed: false`, `execution_status: "not_executed"`
- `execution_reason`: "Insufficient balance"
- Balance info stored

---

## Viewing Signals

### Rails Console

```ruby
# Recent signals
TradingSignal.recent.limit(20)

# Signals with details
TradingSignal.recent.limit(10).each do |signal|
  puts "#{signal.symbol} - #{signal.direction} - #{signal.executed? ? 'EXECUTED' : 'NOT EXECUTED'}"
  puts "  Entry: ₹#{signal.entry_price}, Qty: #{signal.quantity}"
  puts "  Confidence: #{signal.confidence}%, RR: #{signal.risk_reward_ratio}:1"
  puts "  Reason: #{signal.execution_reason}" unless signal.executed?
  puts "  Balance: ₹#{signal.available_balance} / ₹#{signal.required_balance}"
  puts "  Shortfall: ₹#{signal.balance_shortfall}" if signal.balance_shortfall > 0
end
```

### Database Queries

```sql
-- All signals with execution status
SELECT 
  symbol, 
  direction, 
  entry_price, 
  quantity,
  executed,
  execution_status,
  execution_reason,
  available_balance,
  required_balance,
  balance_shortfall
FROM trading_signals
ORDER BY signal_generated_at DESC
LIMIT 50;

-- Signals not executed due to balance
SELECT 
  symbol,
  direction,
  entry_price * quantity as order_value,
  available_balance,
  balance_shortfall,
  execution_reason
FROM trading_signals
WHERE executed = false 
  AND balance_shortfall > 0
ORDER BY balance_shortfall DESC;

-- Execution success rate by symbol
SELECT 
  symbol,
  COUNT(*) as total_signals,
  SUM(CASE WHEN executed THEN 1 ELSE 0 END) as executed_count,
  ROUND(SUM(CASE WHEN executed THEN 1 ELSE 0 END)::numeric / COUNT(*) * 100, 2) as success_rate
FROM trading_signals
GROUP BY symbol
ORDER BY total_signals DESC;
```

---

## Benefits

### 1. Complete Audit Trail

- Every recommendation is tracked
- Know what was recommended even if not executed
- Understand why signals weren't executed

### 2. Performance Analysis

- Compare executed vs not executed signals
- Analyze which signals would have been profitable
- Identify patterns in execution failures

### 3. Balance Management

- Track balance requirements over time
- Identify when balance was insufficient
- Plan capital allocation based on historical signals

### 4. Strategy Improvement

- Review signals that weren't executed
- Understand if balance constraints are limiting opportunities
- Adjust risk limits based on signal analysis

---

## Migration

Run the migration to create the table:

```bash
rails db:migrate
```

This creates the `trading_signals` table with all necessary fields and indexes.

---

## Model Methods

### Query Scopes

```ruby
TradingSignal.executed           # Executed signals
TradingSignal.not_executed       # Not executed signals
TradingSignal.pending_approval   # Pending approval
TradingSignal.failed             # Failed execution
TradingSignal.paper              # Paper trading signals
TradingSignal.live               # Live trading signals
TradingSignal.recent             # Recent signals
TradingSignal.by_symbol(symbol)  # By symbol
TradingSignal.by_direction(dir)   # By direction
```

### Instance Methods

```ruby
signal.executed?              # Check if executed
signal.not_executed?         # Check if not executed
signal.pending_approval?     # Check if pending approval
signal.failed?               # Check if failed
signal.long?                 # Check if long
signal.short?                # Check if short
signal.paper_trading?        # Check if paper trading
signal.live_trading?         # Check if live trading
signal.insufficient_balance? # Check if balance was insufficient
signal.risk_limit_exceeded?  # Check if risk limit exceeded
```

### Update Methods

```ruby
# Mark as executed
signal.mark_as_executed!(
  execution_type: "paper",
  paper_position: position,
  metadata: { ... }
)

# Mark as not executed
signal.mark_as_not_executed!(
  reason: "Insufficient balance",
  error: nil,
  metadata: { ... }
)

# Mark as failed
signal.mark_as_failed!(
  reason: "Execution failed",
  error: "Error message",
  metadata: { ... }
)

# Mark as pending approval
signal.mark_as_pending_approval!(
  reason: "Manual approval required",
  metadata: { ... }
)
```

---

## Simulation & What-If Analysis

### Simulate Not-Executed Signals

You can simulate what would have happened if you had executed signals that weren't executed (due to insufficient balance, etc.):

```ruby
# Simulate a specific signal
signal = TradingSignal.find(123)
result = signal.simulate!

# Simulate all not-executed signals
TradingSignals::Simulator.simulate_all_not_executed

# Simulate with custom end date
signal.simulate!(end_date: Date.today - 5.days)
```

### Simulation Results

After simulation, the signal record includes:
- `simulated_exit_price` - Price at which it would have exited
- `simulated_exit_date` - Date of exit
- `simulated_exit_reason` - Why it exited (sl_hit, tp_hit, time_based)
- `simulated_pnl` - Profit/Loss amount
- `simulated_pnl_pct` - Profit/Loss percentage
- `simulated_holding_days` - Days held

### Performance Analysis

Compare executed vs simulated performance:

```ruby
# Analyze all signals
analysis = TradingSignals::PerformanceAnalyzer.analyze

# Compare executed vs simulated
comparison = analysis[:comparison]
puts "Executed P&L: ₹#{comparison[:executed_total_pnl]}"
puts "Simulated P&L: ₹#{comparison[:simulated_total_pnl]}"
puts "Opportunity Cost: ₹#{comparison[:opportunity_cost]}"
```

### Rake Tasks

```bash
# Simulate all not-executed signals
rails trading_signals:simulate_all

# Simulate a specific signal
rails trading_signals:simulate[123]

# Analyze performance
rails trading_signals:analyze

# List signals with insufficient balance
rails trading_signals:list_insufficient_balance
```

### Example: Understanding Paper Mode Performance

```ruby
# Get all signals that weren't executed due to balance
missed_signals = TradingSignal.not_executed
  .where("execution_reason LIKE ?", "%Insufficient%")
  .where(simulated: true)

# Calculate what you would have made
total_missed_pnl = missed_signals.sum(:simulated_pnl)
puts "Total missed opportunity: ₹#{total_missed_pnl}"

# Compare with what you actually made
executed_signals = TradingSignal.executed.paper
  .joins(:paper_position)
  .where.not(paper_positions: { status: "open" })

actual_pnl = executed_signals.sum { |s| s.paper_position.realized_pnl || 0 }
puts "Actual P&L: ₹#{actual_pnl}"
puts "What-if P&L: ₹#{total_missed_pnl}"
puts "Combined potential: ₹#{actual_pnl + total_missed_pnl}"
```

---

## Summary

All trading recommendations are now:
- ✅ **Persisted** in the database
- ✅ **Tracked** with execution status
- ✅ **Linked** to orders (live) or positions (paper)
- ✅ **Annotated** with balance information
- ✅ **Simulated** for what-if analysis
- ✅ **Queryable** for analysis

This provides complete visibility into:
- What signals were generated
- Which ones were executed
- Why some weren't executed
- Balance requirements and shortfalls
- **What would have happened if you had executed them** (simulation)
- **Comparison of actual vs simulated performance**
- Historical performance of recommendations
