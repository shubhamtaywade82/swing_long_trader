# What-If Analysis: Understanding Paper Mode Performance

**Simulate trades that weren't executed to understand what would have happened**

---

## Overview

When trading signals aren't executed (due to insufficient balance, risk limits, etc.), you can now **simulate** what would have happened if you had executed them. This helps you understand:

- **What you missed** - Profit/loss from signals you couldn't execute
- **System performance** - How well your strategy would have performed with more capital
- **Opportunity cost** - The difference between what you made vs what you could have made
- **Balance impact** - How much capital you need to capture more opportunities

---

## Quick Start

### 1. Simulate All Not-Executed Signals

```bash
# Simulate all signals that weren't executed
rails trading_signals:simulate_all
```

This will:
- Find all signals marked as `not_executed`
- Simulate their execution using historical candle data
- Calculate exit price, P&L, holding days
- Update signal records with simulation results

### 2. Analyze Performance

```bash
# Get comprehensive performance analysis
rails trading_signals:analyze
```

This shows:
- Executed signals performance (actual P&L)
- Simulated signals performance (what-if P&L)
- Comparison between executed vs simulated
- Opportunity cost analysis

### 3. View Specific Signals

```bash
# List signals with insufficient balance
rails trading_signals:list_insufficient_balance
```

---

## How Simulation Works

### Simulation Process

1. **Load Historical Candles**
   - Loads daily candles from signal generation date
   - Uses actual market data for simulation

2. **Simulate Entry**
   - Uses signal's entry price and date
   - Assumes entry at signal generation time

3. **Check Exit Conditions**
   - **Stop Loss Hit**: Exits when price hits stop loss
   - **Take Profit Hit**: Exits when price hits take profit
   - **Time-Based**: Exits at end date if no SL/TP hit

4. **Calculate P&L**
   - Calculates profit/loss based on entry and exit prices
   - Accounts for direction (long/short)
   - Stores P&L amount and percentage

### Simulation Results

After simulation, each signal includes:

```ruby
signal.simulated_exit_price      # Exit price
signal.simulated_exit_date       # Exit date
signal.simulated_exit_reason     # sl_hit, tp_hit, time_based
signal.simulated_pnl             # Profit/Loss amount
signal.simulated_pnl_pct         # Profit/Loss percentage
signal.simulated_holding_days    # Days held
```

---

## Usage Examples

### Example 1: Understand Missed Opportunities

```ruby
# Get all signals that weren't executed due to balance
missed_signals = TradingSignal.not_executed
  .where("execution_reason LIKE ?", "%Insufficient%")
  .simulated

# Calculate total missed P&L
total_missed = missed_signals.sum(:simulated_pnl)
puts "Total missed opportunity: ₹#{total_missed.round(2)}"

# Count winners vs losers
winners = missed_signals.where("simulated_pnl > 0").count
losers = missed_signals.where("simulated_pnl < 0").count
puts "Winners: #{winners}, Losers: #{losers}"
```

### Example 2: Compare Executed vs Simulated

```ruby
# Get executed paper positions
executed = TradingSignal.executed.paper
  .joins(:paper_position)
  .where.not(paper_positions: { status: "open" })

actual_pnl = executed.sum do |s|
  s.paper_position.closed? ? s.paper_position.realized_pnl : s.paper_position.unrealized_pnl
end

# Get simulated not-executed signals
simulated = TradingSignal.not_executed.simulated
simulated_pnl = simulated.sum(:simulated_pnl)

puts "Actual P&L (executed): ₹#{actual_pnl.round(2)}"
puts "Simulated P&L (missed): ₹#{simulated_pnl.round(2)}"
puts "Combined potential: ₹#{(actual_pnl + simulated_pnl).round(2)}"
puts "Opportunity cost: ₹#{(simulated_pnl - actual_pnl).round(2)}"
```

### Example 3: Analyze by Symbol

```ruby
# Find symbols with most missed opportunities
missed_by_symbol = TradingSignal.not_executed
  .simulated
  .group(:symbol)
  .sum(:simulated_pnl)
  .sort_by { |_k, v| -v }

puts "Top missed opportunities by symbol:"
missed_by_symbol.first(10).each do |symbol, pnl|
  puts "  #{symbol}: ₹#{pnl.round(2)}"
end
```

### Example 4: Balance Impact Analysis

```ruby
# Calculate how much capital was needed
signals_needing_capital = TradingSignal.not_executed
  .where("balance_shortfall > 0")
  .simulated

total_shortfall = signals_needing_capital.sum(:balance_shortfall)
total_missed_pnl = signals_needing_capital.sum(:simulated_pnl)

puts "Total capital shortfall: ₹#{total_shortfall.round(2)}"
puts "Total missed P&L: ₹#{total_missed_pnl.round(2)}"
puts "ROI if capital added: #{(total_missed_pnl / total_shortfall * 100).round(2)}%"
```

### Example 5: Performance Metrics

```ruby
# Get comprehensive analysis
analysis = TradingSignals::PerformanceAnalyzer.analyze

# Executed signals stats
exec = analysis[:executed_signals]
puts "Executed Signals:"
puts "  Count: #{exec[:total]}"
puts "  Total P&L: ₹#{exec[:paper_total_pnl]}"
puts "  Avg P&L: ₹#{exec[:paper_avg_pnl]}"
puts "  Win Rate: #{exec[:paper_win_rate]}%"

# Simulated signals stats
sim = analysis[:simulated_signals]
puts "\nSimulated Signals:"
puts "  Count: #{sim[:total]}"
puts "  Total P&L: ₹#{sim[:total_pnl]}"
puts "  Avg P&L: ₹#{sim[:avg_pnl]}"
puts "  Win Rate: #{sim[:win_rate]}%"
puts "  SL Hits: #{sim[:sl_hit_count]}"
puts "  TP Hits: #{sim[:tp_hit_count]}"

# Comparison
if analysis[:comparison]
  comp = analysis[:comparison]
  puts "\nComparison:"
  puts "  Opportunity Cost: ₹#{comp[:opportunity_cost]}"
  puts "  Opportunity Cost %: #{comp[:opportunity_cost_pct]}%"
end
```

---

## Understanding Results

### Exit Reasons

- **`sl_hit`** - Stop loss was hit (loss)
- **`tp_hit`** - Take profit was hit (profit)
- **`time_based`** - Exited at end date (could be profit or loss)

### P&L Interpretation

- **Positive P&L** - Would have been profitable
- **Negative P&L** - Would have been a loss
- **Zero P&L** - Breakeven

### Win Rate

- **High win rate** - Strategy is working well, but capital constraints limiting execution
- **Low win rate** - Maybe good that some signals weren't executed
- **Compare executed vs simulated** - See if capital constraints are filtering out bad trades

---

## Practical Use Cases

### 1. Capital Planning

```ruby
# How much capital do I need to capture top opportunities?
top_missed = TradingSignal.not_executed
  .simulated
  .where("simulated_pnl > 0")
  .order(simulated_pnl: :desc)
  .limit(10)

total_capital_needed = top_missed.sum(:required_balance)
total_potential_pnl = top_missed.sum(:simulated_pnl)

puts "Top 10 missed opportunities:"
puts "  Capital needed: ₹#{total_capital_needed.round(2)}"
puts "  Potential P&L: ₹#{total_potential_pnl.round(2)}"
puts "  ROI: #{(total_potential_pnl / total_capital_needed * 100).round(2)}%"
```

### 2. Strategy Validation

```ruby
# Is the strategy working? Check simulated performance
simulated = TradingSignal.not_executed.simulated

win_rate = (simulated.where("simulated_pnl > 0").count.to_f / simulated.count * 100).round(2)
avg_pnl = simulated.average(:simulated_pnl)&.round(2) || 0

puts "Simulated Performance:"
puts "  Win Rate: #{win_rate}%"
puts "  Avg P&L: ₹#{avg_pnl}"

if win_rate > 50 && avg_pnl > 0
  puts "✅ Strategy looks good - consider adding capital"
elsif win_rate < 40 || avg_pnl < 0
  puts "⚠️ Strategy may need improvement"
end
```

### 3. Risk Assessment

```ruby
# What's the worst-case scenario for missed signals?
worst_loss = TradingSignal.not_executed
  .simulated
  .minimum(:simulated_pnl)

best_profit = TradingSignal.not_executed
  .simulated
  .maximum(:simulated_pnl)

puts "Missed Signals Risk:"
puts "  Worst loss: ₹#{worst_loss.round(2)}"
puts "  Best profit: ₹#{best_profit.round(2)}"
```

---

## Rake Tasks Reference

### Simulate All

```bash
rails trading_signals:simulate_all
```

Simulates all not-executed signals that haven't been simulated yet.

### Simulate Specific Signal

```bash
rails trading_signals:simulate[signal_id]
```

Example:
```bash
rails trading_signals:simulate[123]
```

### Analyze Performance

```bash
rails trading_signals:analyze
```

Shows comprehensive performance analysis including executed vs simulated comparison.

### List Insufficient Balance Signals

```bash
rails trading_signals:list_insufficient_balance
```

Lists recent signals that weren't executed due to insufficient balance, with simulation results if available.

---

## Best Practices

### 1. Regular Simulation

Run simulation regularly to keep data up-to-date:

```bash
# Add to cron or scheduled job
# Run daily after market close
rails trading_signals:simulate_all
```

### 2. Review Analysis Weekly

```bash
# Weekly performance review
rails trading_signals:analyze
```

### 3. Monitor Opportunity Cost

Track opportunity cost over time to understand capital needs:

```ruby
# Weekly opportunity cost tracking
weekly_analysis = TradingSignals::PerformanceAnalyzer.analyze
opportunity_cost = weekly_analysis[:comparison][:opportunity_cost]
# Log or store for trend analysis
```

### 4. Balance Planning

Use simulation results to plan capital allocation:

```ruby
# Calculate optimal capital based on missed opportunities
missed_profitable = TradingSignal.not_executed
  .simulated
  .where("simulated_pnl > 0")
  .where("balance_shortfall > 0")

optimal_capital = missed_profitable.sum(:balance_shortfall)
potential_return = missed_profitable.sum(:simulated_pnl)

puts "To capture profitable opportunities:"
puts "  Add capital: ₹#{optimal_capital.round(2)}"
puts "  Potential return: ₹#{potential_return.round(2)}"
```

---

## Summary

The simulation feature allows you to:

✅ **Understand what you missed** - See P&L from signals you couldn't execute  
✅ **Compare performance** - Actual vs simulated results  
✅ **Plan capital** - Know how much capital you need  
✅ **Validate strategy** - See if strategy would work with more capital  
✅ **Track opportunity cost** - Measure the cost of capital constraints  

This gives you complete visibility into your paper trading performance, including what would have happened if you had more capital!
