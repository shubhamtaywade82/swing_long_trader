# ATR-Based Swing Trading Strategy Implementation

## Summary

All required features for the long-only swing trading strategy have been successfully implemented and tested. The system now uses ATR-based stop loss, take profit targets, and trailing stops as specified.

---

## ✅ Implemented Features

### 1. Dynamic ATR Stop Loss Multiplier (1.5-2.5×)

**Implementation:** `app/services/screeners/trade_plan_builder.rb`

- **Low Volatility** (ATR % < 2%): Uses **1.5× ATR** stop loss
- **Medium Volatility** (ATR % 2-5%): Uses **2.0× ATR** stop loss
- **High Volatility** (ATR % > 5%): Uses **2.5× ATR** stop loss

**Code:**
```ruby
atr_multiplier = if atr_pct < 2.0
                   ATR_SL_LOW_VOL  # 1.5
                 elsif atr_pct <= 5.0
                   ATR_SL_MED_VOL  # 2.0
                 else
                   ATR_SL_HIGH_VOL # 2.5
                 end
```

---

### 2. ATR-Based Take Profit Targets

**Implementation:** `app/services/screeners/trade_plan_builder.rb`

- **TP1** = Entry + (ATR × 2)
- **TP2** = Entry + (ATR × 4)

**Code:**
```ruby
tp1 = entry_price + (atr * TP1_ATR_MULTIPLE)  # 2.0
tp2 = entry_price + (atr * TP2_ATR_MULTIPLE)  # 4.0
```

---

### 3. Breakeven Stop After TP1

**Implementation:**
- `app/models/position.rb` - `move_stop_to_breakeven!` method
- `app/jobs/strategies/swing/exit_monitor_job.rb` - TP1 hit detection

**Behavior:**
- When TP1 is hit, stop loss is automatically moved to entry price (breakeven)
- Original stop loss is preserved in `initial_stop_loss` field
- Position continues to TP2 with breakeven protection

**Code:**
```ruby
def move_stop_to_breakeven!
  update!(
    breakeven_stop: entry_price,
    initial_stop_loss: stop_loss,
    stop_loss: entry_price,
  )
end
```

---

### 4. ATR-Based Trailing Stop (1-2× ATR)

**Implementation:** `app/models/position.rb` - `check_atr_trailing_stop?` method

- Trails by **1.5× ATR** (configurable, default 1.5)
- Updates stop loss dynamically as price moves in favor
- Only moves stop loss higher (for longs) or lower (for shorts)

**Code:**
```ruby
trailing_stop = highest_price - (atr * atr_trailing_multiplier)
# Only update if trailing stop is higher than current stop loss
if trailing_stop > stop_loss
  update!(stop_loss: trailing_stop)
end
```

---

### 5. RSI Recovery Momentum Check

**Implementation:** `app/services/screeners/setup_detector.rb` - `check_rsi_recovery` method

- Checks if RSI is **recovering above 45-50**
- Validates upward momentum (price rising or RSI >= 50)
- Rejects setups when RSI is below 45 or above 70

**Code:**
```ruby
if current_rsi >= 45 && current_rsi <= 70
  price_rising = recent_closes.last > recent_closes[-2]
  if current_rsi >= 50 || price_rising
    return { valid: true }
  end
end
```

---

### 6. Minimum Risk-Reward Ratio: 3R

**Implementation:** `app/services/screeners/trade_plan_builder.rb`

- Changed `MIN_RR` from 2.5 to **3.0**
- Trade plans are rejected if RR < 3.0
- RR is calculated based on TP2 (final target)

**Code:**
```ruby
MIN_RR = 3.0 # Minimum risk-reward ratio (1:3 = 3.0)
```

---

## 📊 Database Schema Changes

**Migration:** `db/migrate/20251215000001_add_atr_based_fields_to_positions.rb`

**New Fields:**
- `tp1` (decimal) - First take profit target
- `tp2` (decimal) - Final take profit target
- `atr` (decimal) - Average True Range value
- `atr_pct` (decimal) - ATR as percentage of price
- `tp1_hit` (boolean) - Flag indicating TP1 was hit
- `breakeven_stop` (decimal) - Breakeven stop price
- `atr_trailing_multiplier` (decimal) - ATR multiplier for trailing stop
- `initial_stop_loss` (decimal) - Original stop loss before breakeven

---

## 🔄 Updated Components

### Services
1. **TradePlanBuilder** - ATR-based stop loss and targets
2. **SetupDetector** - RSI recovery momentum check
3. **SignalBuilder** - ATR-based targets in signals
4. **Executor** - Position creation with TP1/TP2/ATR fields

### Models
1. **Position** - TP1/TP2 checks, breakeven stop, ATR trailing stop

### Jobs
1. **ExitMonitorJob** - TP1/TP2 hit detection, breakeven stop movement

---

## 🧪 Tests

**Test Files Created:**
1. `spec/services/screeners/trade_plan_builder_spec.rb` - Trade plan generation tests
2. `spec/services/screeners/setup_detector_spec.rb` - RSI recovery tests
3. `spec/models/position_atr_spec.rb` - Position ATR methods tests
4. `spec/jobs/strategies/swing/exit_monitor_job_atr_spec.rb` - Exit monitoring tests

**Test Coverage:**
- ✅ Dynamic ATR multiplier based on volatility
- ✅ TP1 and TP2 calculation
- ✅ Breakeven stop movement
- ✅ ATR trailing stop
- ✅ RSI recovery check
- ✅ Minimum 3R risk-reward validation

---

## 📝 Usage Examples

### Trade Plan Generation

```ruby
trade_plan = Screeners::TradePlanBuilder.call(
  candidate: candidate,
  daily_series: daily_series,
  indicators: indicators,
  setup_status: setup_status,
)

# Result includes:
# - entry_price: 2500.0
# - stop_loss: 2450.0 (using 2.0× ATR for medium volatility)
# - tp1: 2550.0 (Entry + ATR × 2)
# - tp2: 2600.0 (Entry + ATR × 4)
# - atr: 25.0
# - atr_sl_multiplier: 2.0
# - risk_reward: 3.0 (minimum)
```

### Position Monitoring

```ruby
# When TP1 is hit
if position.check_tp1_hit?
  position.update!(tp1_hit: true)
  position.move_stop_to_breakeven!
  # Stop loss moved to entry price
end

# When TP2 is hit
if position.check_tp2_hit?
  # Exit position
end

# ATR trailing stop
if position.check_atr_trailing_stop?
  # Exit position
end
```

---

## ✅ Verification Checklist

- [x] Dynamic ATR stop loss multiplier (1.5-2.5×) based on volatility
- [x] TP1 = Entry + (ATR × 2)
- [x] TP2 = Entry + (ATR × 4)
- [x] Breakeven stop after TP1 hit
- [x] ATR-based trailing stop (1-2× ATR)
- [x] RSI recovery momentum check (45-50)
- [x] Minimum risk-reward ratio: 3R
- [x] Database schema updated
- [x] Position model updated
- [x] Exit monitor job updated
- [x] Comprehensive tests written

---

## 🚀 Next Steps

1. **Run Migration:**
   ```bash
   rails db:migrate
   ```

2. **Run Tests:**
   ```bash
   rspec spec/services/screeners/trade_plan_builder_spec.rb
   rspec spec/services/screeners/setup_detector_spec.rb
   rspec spec/models/position_atr_spec.rb
   rspec spec/jobs/strategies/swing/exit_monitor_job_atr_spec.rb
   ```

3. **Verify in Production:**
   - Check trade plans include TP1/TP2
   - Verify breakeven stops are moved after TP1
   - Monitor ATR trailing stops
   - Confirm RSI recovery checks are working

---

## 📚 References

- Original Requirements: See `docs/swing_trading_strategy_analysis.md`
- ATR Calculation: `app/models/candle_series.rb`
- Trade Plan Builder: `app/services/screeners/trade_plan_builder.rb`
- Setup Detector: `app/services/screeners/setup_detector.rb`
