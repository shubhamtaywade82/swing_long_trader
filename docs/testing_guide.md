# Testing Guide

This guide explains how to test all components of the swing trading system using Rails console, Rails runner, and rake tasks.

---

## Quick Start

### Rails Console

```bash
rails console
```

Then load helpers:
```ruby
load 'lib/console_helpers.rb'
```

### Rails Runner

```bash
rails runner script/test_console.rb [command] [args...]
```

### Rake Tasks

```bash
rake test:mtf:analyzer[RELIANCE]
rake test:capital:portfolio[Test Portfolio,paper,500000]
rake test:all[RELIANCE]
```

---

## Multi-Timeframe Testing

### 1. Test Multi-Timeframe Analyzer

**Rake Task:**
```bash
rake test:mtf:analyzer[RELIANCE]
rake test:mtf:analyzer[TCS]
```

**Rails Console:**
```ruby
mtf_analyze("RELIANCE")
mtf_analyze("TCS")
```

**Rails Runner:**
```bash
rails runner script/test_console.rb mtf_analyzer RELIANCE
```

**What it tests:**
- Loads 15m, 1h, 1d, 1w candles
- Calculates indicators per timeframe
- Analyzes trend/momentum alignment
- Identifies support/resistance levels
- Generates entry recommendations

---

### 2. Test Multi-Timeframe Screener

**Rake Task:**
```bash
rake test:mtf:screener[10]  # Top 10 candidates
rake test:mtf:screener[20]  # Top 20 candidates
```

**Rails Console:**
```ruby
mtf_screen(10)  # Top 10
mtf_screen(20)  # Top 20
```

**Rails Runner:**
```bash
rails runner script/test_console.rb mtf_screener 10
```

**What it tests:**
- Screens instruments using multi-timeframe analysis
- Combines base score + MTF score
- Returns ranked candidates with MTF metadata

---

### 3. Test Signal Builder

**Rake Task:**
```bash
rake test:mtf:signal[RELIANCE]
rake test:mtf:signal[TCS]
```

**Rails Console:**
```ruby
mtf_signal("RELIANCE")
mtf_signal("TCS")
```

**Rails Runner:**
```bash
rails runner script/test_console.rb mtf_signal RELIANCE
```

**What it tests:**
- Generates swing trading signals
- Uses MTF data for entry/exit calculations
- Enhances confidence with MTF alignment
- Uses MTF S/R for stop loss/take profit

---

### 4. Test AI Evaluator

**Rake Task:**
```bash
rake test:mtf:ai_eval[RELIANCE]
```

**Rails Console:**
```ruby
ai_eval("RELIANCE")
```

**Rails Runner:**
```bash
rails runner script/test_console.rb ai_eval RELIANCE
```

**What it tests:**
- Calls OpenAI API with MTF data
- Evaluates timeframe alignment
- Assesses entry timing
- Provides risk assessment

---

### 5. Test AI Ranker

**Rake Task:**
```bash
rake test:mtf:ai_rank[5]  # Rank top 5
```

**What it tests:**
- Ranks candidates using AI
- Considers MTF alignment in scoring
- Provides AI summaries

---

### 6. Test Complete Flow

**Rake Task:**
```bash
rake test:mtf:full_flow[RELIANCE]
```

**What it tests:**
- Complete flow: MTF Analysis → Signal → AI Evaluation
- Shows all steps and results

---

## Capital Allocation Testing

### 1. Test Portfolio Creation

**Rake Task:**
```bash
rake test:capital:portfolio[Test Portfolio,paper,500000]
rake test:capital:portfolio[Live Portfolio,live,1000000]
```

**Rails Console:**
```ruby
create_portfolio("Test", 500000)
create_portfolio("Live", 1000000)
```

**Rails Runner:**
```bash
rails runner script/test_console.rb capital_portfolio "Test Portfolio" 500000
```

**What it tests:**
- Creates capital allocation portfolio
- Initializes capital buckets
- Sets up risk configuration
- Rebalances capital based on phase

---

### 2. Test Position Sizing

**Rake Task:**
```bash
rake test:capital:position_size[RELIANCE,2500,2400]
rake test:capital:position_size[TCS,3500,3400]
```

**Rails Console:**
```ruby
position_size("RELIANCE", 2500, 2400)
position_size("TCS", 3500, 3400, "Test Portfolio")
```

**Rails Runner:**
```bash
rails runner script/test_console.rb position_size RELIANCE 2500 2400
```

**What it tests:**
- Calculates risk-based position size
- Applies exposure caps
- Checks available capital
- Returns quantity, capital, risk amounts

---

### 3. Test Risk Manager

**Rake Task:**
```bash
rake test:capital:risk_manager[Test Portfolio]
```

**Rails Console:**
```ruby
risk_check("Test Portfolio")
```

**What it tests:**
- Checks daily loss limits
- Checks max positions
- Checks drawdown limits
- Checks consecutive losses
- Returns allowed/blocked status

---

### 4. Test Capital Rebalancing

**Rake Task:**
```bash
rake test:capital:rebalance[Test Portfolio,750000]
```

**What it tests:**
- Rebalances capital when equity changes
- Adjusts allocation based on phase
- Updates swing/long-term/cash buckets

---

## Complete Testing

### Run All Tests

**Rake Task:**
```bash
rake test:all[RELIANCE]
rake test:all[TCS]
```

**What it tests:**
- All MTF tests (analyzer, signal, AI eval)
- All capital allocation tests (portfolio, position size, risk manager)

---

### Quick Test

**Rake Task:**
```bash
rake test:quick[RELIANCE]
```

**What it tests:**
- Quick MTF analyzer test only

---

## Console Helper Methods

When you load `lib/console_helpers.rb` in Rails console, you get:

### Multi-Timeframe Methods

```ruby
# Analyze instrument with MTF
mtf_analyze("RELIANCE")
mtf_analyze("TCS")

# Screen candidates
candidates = mtf_screen(10)

# Generate signal
signal = mtf_signal("RELIANCE")

# AI evaluation
ai_result = ai_eval("RELIANCE")
```

### Capital Allocation Methods

```ruby
# Create portfolio
portfolio = create_portfolio("Test", 500000)

# Calculate position size
size_result = position_size("RELIANCE", 2500, 2400)

# Check risk
risk_result = risk_check("Test Portfolio")
```

---

## Example Workflows

### Workflow 1: Analyze a Stock

```ruby
# Rails console
load 'lib/console_helpers.rb'

# Step 1: Multi-timeframe analysis
analysis = mtf_analyze("RELIANCE")

# Step 2: Generate signal
signal = mtf_signal("RELIANCE")

# Step 3: AI evaluation
ai_result = ai_eval("RELIANCE")

# Step 4: Check if we can take the trade
portfolio = create_portfolio("My Portfolio", 500000)
size_result = position_size("RELIANCE", signal[:entry_price], signal[:sl])
risk_result = risk_check("My Portfolio")
```

### Workflow 2: Screen and Rank

```ruby
# Rails console
load 'lib/console_helpers.rb'

# Step 1: Screen candidates
candidates = mtf_screen(20)

# Step 2: AI rank top candidates
ranked = Screeners::AIRanker.call(candidates: candidates.first(10), limit: 5)

# Step 3: Generate signals for top ranked
ranked.each do |candidate|
  instrument = Instrument.find(candidate[:instrument_id])
  daily_series = instrument.load_daily_candles(limit: 100)
  weekly_series = instrument.load_weekly_candles(limit: 52)
  
  signal = Strategies::Swing::SignalBuilder.call(
    instrument: instrument,
    daily_series: daily_series,
    weekly_series: weekly_series,
  )
  
  puts "#{candidate[:symbol]}: Entry ₹#{signal[:entry_price]}" if signal
end
```

### Workflow 3: Test Position Sizing

```ruby
# Rails console
load 'lib/console_helpers.rb'

# Create portfolio
portfolio = create_portfolio("Test", 500000)

# Test different entry/SL combinations
[
  ["RELIANCE", 2500, 2400],
  ["TCS", 3500, 3400],
  ["INFY", 1500, 1450],
].each do |symbol, entry, sl|
  result = position_size(symbol, entry, sl, "Test")
  if result
    puts "#{symbol}: #{result[:quantity]} shares, Risk: ₹#{result[:risk_amount].round(2)}"
  end
end
```

---

## Troubleshooting

### Common Issues

1. **Instrument not found**
   ```ruby
   # Check if instrument exists
   Instrument.find_by(symbol_name: "RELIANCE")
   
   # Import instruments if needed
   rake instruments:import
   ```

2. **No candles available**
   ```ruby
   # Check candles
   instrument = Instrument.find_by(symbol_name: "RELIANCE")
   instrument.has_candles?(timeframe: "1D")
   instrument.has_candles?(timeframe: "1W")
   
   # Ingest candles if needed
   rake candles:daily:ingest
   rake candles:weekly:ingest
   ```

3. **OpenAI API errors**
   ```ruby
   # Check API key
   ENV["OPENAI_API_KEY"]
   
   # Check rate limits
   # Default: 50 calls/day
   ```

4. **Portfolio not found**
   ```ruby
   # Create portfolio first
   create_portfolio("Test Portfolio", 500000)
   ```

---

## Performance Tips

1. **Cache Results**: MTF analysis and AI evaluations are cached
2. **Batch Testing**: Use rake tasks for batch testing multiple instruments
3. **Limit Candidates**: Use reasonable limits (10-20) for screeners
4. **Skip Intraday**: Set `include_intraday: false` if testing many instruments

---

## Summary

✅ **Rake Tasks**: `rake test:mtf:*` and `rake test:capital:*`  
✅ **Rails Console**: Load `lib/console_helpers.rb` for helper methods  
✅ **Rails Runner**: Use `script/test_console.rb` for scripting  
✅ **Complete Flow**: Use `rake test:all` for comprehensive testing  

All testing utilities are ready to use! 🚀
