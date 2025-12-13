# Capital Allocation & Multiple Timeframe Analysis

## Overview

This document explains how the system handles:
1. **Multiple Timeframe Analysis** - Using daily and weekly timeframes for decision-making
2. **Capital-Based Position Sizing** - Calculating position sizes based on available capital and risk

---

## 1. Multiple Timeframe Analysis

### Current Implementation

The system uses a **hierarchical timeframe approach** where higher timeframes (weekly) provide trend context and lower timeframes (daily) provide entry timing.

#### Timeframe Structure

```
Weekly (1W) → Trend Context & Filter
    ↓
Daily (1D) → Entry Signals & Execution
```

#### How It Works

**1. Data Loading (`CandleLoader` concern)**
```ruby
# Load daily candles
daily_series = instrument.load_daily_candles(limit: 100)

# Load weekly candles  
weekly_series = instrument.load_weekly_candles(limit: 52)
```

**2. Long-Term Screener (`LongtermScreener`)**
- **Requires both timeframes**: Checks for `1D` and `1W` candles before analysis
- **Weekly analysis**: Calculates weekly indicators (EMA20, EMA50, Supertrend, ADX, RSI)
- **Daily analysis**: Calculates daily indicators for entry timing
- **Trend alignment**: Requires weekly trend to be bullish before considering daily entry

```ruby
# From longterm_screener.rb
def passes_basic_filters?(instrument)
  return false unless instrument.has_candles?(timeframe: "1D")
  return false unless instrument.has_candles?(timeframe: "1W")  # Required!
  true
end

def calculate_score(daily_series, weekly_series, daily_indicators, weekly_indicators)
  score = 0.0
  
  # Weekly trend requirement - 40 points
  if weekly_indicators[:ema20] > weekly_indicators[:ema50]
    score += 20  # Weekly EMA bullish
  end
  
  if weekly_indicators[:supertrend][:direction] == :bullish
    score += 20  # Weekly Supertrend bullish
  end
  
  # Daily trend alignment - 30 points
  if daily_indicators[:ema20] > daily_indicators[:ema50]
    score += 15  # Daily EMA bullish
  end
  
  # ... more scoring logic
end
```

**3. Swing Screener (`SwingScreener`)**
- **Primary timeframe**: Daily (`1D`) only
- **No weekly requirement**: Focuses on shorter-term swing setups
- **Single timeframe analysis**: Calculates indicators on daily candles

```ruby
# From swing_screener.rb
def passes_basic_filters?(instrument)
  return false unless instrument.has_candles?(timeframe: "1D")
  # No weekly requirement for swing trading
  true
end
```

**4. Signal Builder (`SignalBuilder`)**
- **Accepts optional weekly series**: Can use weekly for trend confirmation
- **Primary analysis on daily**: Entry/exit calculations use daily timeframe
- **Weekly used for confidence**: Higher confidence if weekly trend aligns

```ruby
# From signal_builder.rb
def initialize(instrument:, daily_series:, weekly_series: nil, config: {})
  @daily_series = daily_series  # Required
  @weekly_series = weekly_series  # Optional
end

def calculate_confidence(direction)
  # Can incorporate weekly trend alignment for higher confidence
  # But primary signals come from daily timeframe
end
```

### Timeframe Usage Summary

| Component | Primary TF | Secondary TF | Purpose |
|-----------|-----------|-------------|---------|
| Long-Term Screener | Daily (1D) | Weekly (1W) | Trend filter + Entry timing |
| Swing Screener | Daily (1D) | None | Entry signals only |
| Signal Builder | Daily (1D) | Weekly (1W) optional | Entry/exit calculation |
| Long-Term Evaluator | Daily (1D) | Weekly (1W) | Entry conditions check |

---

## 2. Capital-Based Position Sizing

### Current Implementation (Before Capital Allocation System)

#### Old Approach: Fixed Account Size

**1. Signal Builder (`SignalBuilder`)**
```ruby
def calculate_position_size(entry_price, stop_loss)
  risk_pct = @risk_config[:risk_per_trade_pct] || 2.0
  account_size = @risk_config[:account_size] || 100_000  # Fixed!
  
  risk_amount = account_size * (risk_pct / 100.0)
  risk_per_share = entry_price - stop_loss
  
  quantity = (risk_amount / risk_per_share).floor
  
  # Apply lot size
  if @instrument.lot_size && @instrument.lot_size > 1
    quantity = (quantity / @instrument.lot_size) * @instrument.lot_size
  end
  
  [quantity, 1].max
end
```

**Problems:**
- ❌ Uses fixed `account_size` from config (default ₹1L)
- ❌ Doesn't check actual available capital
- ❌ No capital bucketing (swing vs long-term)
- ❌ No exposure caps per position
- ❌ Risk calculated on fixed amount, not actual portfolio equity

**2. Paper Trading Risk Manager (`PaperTrading::RiskManager`)**
```ruby
def check_capital_available
  required_capital = @signal[:entry_price] * @signal[:qty]
  
  if required_capital > @portfolio.available_capital
    return { success: false, error: "Insufficient capital" }
  end
  
  { success: true }
end

def check_max_position_size
  max_pct = @risk_config[:max_position_size_pct] || 10.0
  max_value = (@portfolio.capital * max_pct / 100.0)  # Uses capital, not equity
  order_value = @signal[:entry_price] * @signal[:qty]
  
  if order_value > max_value
    return { success: false, error: "Exceeds max position size" }
  end
end
```

**Problems:**
- ⚠️ Checks capital availability AFTER position size is calculated
- ⚠️ Uses `portfolio.capital` instead of `total_equity`
- ⚠️ No risk-based sizing, only capital-based checks

---

### New Implementation: Capital Allocation System

#### Risk-Based Position Sizing (`Swing::PositionSizer`)

**Step-by-Step Process:**

```ruby
# 1. Calculate risk per share
risk_per_share = |entry_price - stop_loss|

# 2. Get risk amount from portfolio equity (not fixed account size)
risk_amount = portfolio.total_equity * (risk_per_trade / 100.0)

# 3. Calculate raw quantity based on risk
raw_qty = risk_amount / risk_per_share

# 4. Apply exposure cap (max position exposure %)
max_exposure_amount = portfolio.total_equity * (max_position_exposure / 100.0)
max_qty_by_exposure = max_exposure_amount / entry_price

# 5. Final quantity = min(raw_qty, max_qty_by_exposure)
final_quantity = [raw_qty, max_qty_by_exposure].min.floor

# 6. Check available swing capital
if (final_quantity * entry_price) > portfolio.available_swing_capital
  # Recalculate with available capital
  final_quantity = (portfolio.available_swing_capital / entry_price).floor
end
```

**Key Improvements:**

✅ **Risk-first approach**: Size based on risk amount, not capital amount  
✅ **Uses actual portfolio equity**: `portfolio.total_equity` instead of fixed config  
✅ **Capital bucketing**: Uses `available_swing_capital` (partitioned capital)  
✅ **Exposure caps**: Limits position size to max % of equity  
✅ **Available capital check**: Ensures sufficient swing capital exists  

#### Example Calculation

**Portfolio State:**
- Total Equity: ₹5,00,000
- Swing Capital: ₹4,00,000 (80%)
- Available Swing Capital: ₹3,25,200 (after existing positions)

**Trade Signal:**
- Entry: ₹1,000
- Stop Loss: ₹950
- Risk per trade: 1%
- Max position exposure: 15%

**Calculation:**
```ruby
# Step 1: Risk per share
risk_per_share = |1000 - 950| = ₹50

# Step 2: Risk amount
risk_amount = 5,00,000 * 0.01 = ₹5,000

# Step 3: Raw quantity
raw_qty = 5,000 / 50 = 100 shares

# Step 4: Exposure cap
max_exposure = 5,00,000 * 0.15 = ₹75,000
max_qty_by_exposure = 75,000 / 1,000 = 75 shares

# Step 5: Apply exposure cap
final_qty = min(100, 75) = 75 shares

# Step 6: Check available capital
capital_required = 75 * 1,000 = ₹75,000
available = ₹3,25,200 ✅ Sufficient

# Result: 75 shares
# Actual risk: 75 * 50 = ₹3,750 (0.75% of equity)
```

---

## 3. Capital Bucketing System

### How Capital is Partitioned

**Phase-Based Allocation:**

```ruby
# Early Stage (< ₹3L)
swing:      80%
long_term:   0%
cash:       20%

# Growth Phase (₹3L - ₹5L)
swing:      70%
long_term:  20%
cash:       10%

# Mature Phase (₹5L+)
swing:      60%
long_term:  30%
cash:       10%
```

**Automatic Rebalancing:**

```ruby
# From Portfolio::CapitalBucketer
def apply_allocation(allocation)
  total = @portfolio.total_equity
  
  # Calculate target amounts
  target_swing = total * allocation[:swing] / 100.0
  target_long_term = total * allocation[:long_term] / 100.0
  target_cash = total * allocation[:cash] / 100.0
  
  # Adjust for existing positions (can't reduce below current exposure)
  final_swing_capital = [target_swing, current_swing_exposure].max
  final_long_term_capital = [target_long_term, current_long_term_value].max
  
  # Recalculate cash
  final_cash = total - final_swing_capital - final_long_term_capital
  
  # Update portfolio
  @portfolio.update!(
    swing_capital: final_swing_capital,
    long_term_capital: final_long_term_capital,
    available_cash: final_cash
  )
end
```

---

## 4. Integration Flow

### Complete Execution Flow

```
Signal Generated
    ↓
[Multiple Timeframe Analysis]
    ├─ Daily: Entry/Exit signals
    └─ Weekly: Trend confirmation (optional)
    ↓
[Position Sizing]
    ├─ Calculate risk per share
    ├─ Get risk amount from portfolio equity
    ├─ Calculate quantity based on risk
    ├─ Apply exposure cap
    └─ Check available swing capital
    ↓
[Risk Manager Checks]
    ├─ Daily loss limit
    ├─ Max positions
    ├─ Drawdown limit
    └─ Consecutive losses
    ↓
[Capital Availability]
    └─ Verify sufficient swing capital
    ↓
[Execution]
    ├─ Paper Trading Executor
    └─ Live Trading Executor
    ↓
[Ledger Entry]
    └─ Record transaction
```

---

## 5. Key Differences: Old vs New

| Aspect | Old System | New System |
|--------|-----------|------------|
| **Account Size** | Fixed from config (₹1L default) | Dynamic from portfolio equity |
| **Capital Source** | Single pool | Partitioned (swing/long-term/cash) |
| **Position Sizing** | Capital-based | Risk-based |
| **Exposure Caps** | Simple % check | Risk + exposure caps |
| **Capital Check** | After sizing | During sizing |
| **Rebalancing** | Manual | Automatic by phase |
| **Risk Calculation** | Fixed account size | Actual portfolio equity |

---

## 6. Best Practices

### For Multiple Timeframe Analysis

1. **Always check data availability** before analysis
   ```ruby
   return false unless instrument.has_candles?(timeframe: "1D")
   return false unless instrument.has_candles?(timeframe: "1W")  # If needed
   ```

2. **Use weekly for trend context**, daily for entries
   ```ruby
   # Weekly determines IF we trade
   # Daily determines WHEN we trade
   ```

3. **Validate trend alignment** across timeframes
   ```ruby
   weekly_bullish = weekly_indicators[:supertrend][:direction] == :bullish
   daily_bullish = daily_indicators[:supertrend][:direction] == :bullish
   aligned = weekly_bullish && daily_bullish
   ```

### For Capital-Based Sizing

1. **Always use risk-first approach**
   ```ruby
   # ✅ Good: Risk-based
   risk_amount = portfolio.total_equity * risk_pct
   quantity = risk_amount / risk_per_share
   
   # ❌ Bad: Capital-based
   quantity = available_capital / entry_price
   ```

2. **Check capital availability during sizing**
   ```ruby
   # ✅ Good: Check during calculation
   if capital_required > available_capital
     quantity = (available_capital / entry_price).floor
   end
   
   # ❌ Bad: Check after calculation
   quantity = calculate_quantity(...)
   if insufficient_capital
     reject_trade
   end
   ```

3. **Use partitioned capital buckets**
   ```ruby
   # ✅ Good: Use swing capital for swing trades
   available = portfolio.available_swing_capital
   
   # ❌ Bad: Use total capital
   available = portfolio.available_cash
   ```

---

## 7. Migration Path

To migrate existing code to use the new capital allocation system:

1. **Replace Signal Builder sizing**:
   ```ruby
   # Old
   quantity = calculate_position_size(entry_price, stop_loss)
   
   # New
   result = Swing::PositionSizer.call(
     portfolio: portfolio,
     entry_price: entry_price,
     stop_loss: stop_loss,
     instrument: instrument
   )
   quantity = result[:quantity] if result[:success]
   ```

2. **Use Capital Allocation Portfolio**:
   ```ruby
   # Old
   portfolio = PaperPortfolio.find_or_create_default
   
   # New
   portfolio = CapitalAllocationPortfolio.find_or_create_by(
     name: "Paper Portfolio",
     mode: "paper"
   )
   ```

3. **Update risk checks**:
   ```ruby
   # Old
   PaperTrading::RiskManager.check_limits(portfolio: portfolio, signal: signal)
   
   # New
   Portfolio::RiskManager.new(portfolio: portfolio).call
   ```

---

## Summary

The system now provides:

✅ **Proper multiple timeframe analysis** with weekly trend filtering  
✅ **Risk-based position sizing** using actual portfolio equity  
✅ **Capital bucketing** separating swing/long-term/cash  
✅ **Automatic rebalancing** based on portfolio growth phase  
✅ **Exposure caps** preventing over-concentration  
✅ **Real-time capital availability** checks during sizing  

This creates a **professional-grade capital allocation system** that scales from ₹10k to ₹50L+ while maintaining proper risk management.
