# Swing Trading Strategy Implementation Analysis

## Overview
This document compares the current implementation against the specified long-only swing trading strategy requirements for Indian stocks.

---

## ✅ CORRECTLY IMPLEMENTED

### 1. Trend Filters & Entries
- ✅ **Moving Averages**: Price above 50-DMA and 200-DMA check (`SetupDetector`, `SwingScreener`)
- ✅ **EMA Pullbacks**: Entries on pullbacks to 20-50 DMA (`TradePlanBuilder.calculate_entry_price`)
- ✅ **Supertrend**: Supertrend indicator with bullish direction check
- ✅ **MACD**: MACD bullish cross/histogram check (`SwingScreener.calculate_score`)
- ✅ **RSI**: RSI calculation and overbought check (though not specifically 45-50 recovery)

### 2. Indicator Combinations
- ✅ **MA + RSI**: Implemented in scoring (`SwingScreener.calculate_score`)
- ✅ **MA + MACD**: Implemented in scoring
- ✅ **MA + Supertrend**: Implemented in scoring

### 3. Position Sizing
- ✅ **ATR-based sizing**: Position size = Account risk ÷ (ATR × multiple) (`TradePlanBuilder.calculate_quantity`)

---

## ❌ GAPS & MISSING FEATURES

### 1. Stop Loss Using ATR

**Current Implementation:**
```ruby
# TradePlanBuilder.calculate_stop_loss
atr_stop = entry_price - (atr * 2)  # Fixed 2.0 ATR
```

**Required:**
- Initial SL: Entry − (ATR × 1.5 to 2.5)
- Tighten to 1.5× in calm markets (low volatility)
- Widen to 2.5–3× when volatility is high
- Should adapt based on ATR percentage of price

**Gap:** Fixed 2.0 ATR multiplier, no volatility-based adjustment

---

### 2. Targets Using ATR Multiples

**Current Implementation:**
```ruby
# TradePlanBuilder.calculate_take_profit
target = entry_price + (risk * DEFAULT_TP_MULTIPLE)  # 2.5R fixed
```

**Required:**
- TP1 = Entry + (ATR × 2)
- TP2 = Entry + (ATR × 4)
- Move stop to breakeven after TP1
- Trail by 1–2× ATR on daily or 1-hour closes

**Gap:** Uses risk-reward multiples (2.5R) instead of ATR multiples. No TP1/TP2 concept. No breakeven stop after TP1.

---

### 3. Trailing Stop Using ATR

**Current Implementation:**
```ruby
# Position model uses percentage-based trailing stop
trailing_stop = highest_price * (1 - (trailing_stop_pct / 100.0))
```

**Required:**
- Trail by 1–2× ATR on daily or 1-hour closes
- Use ATR chandelier stop concept

**Gap:** Uses percentage-based trailing, not ATR-based

---

### 4. RSI Recovery Check

**Current Implementation:**
```ruby
# Checks RSI > 50 and < 70, but not specifically "recovering above 45-50"
if indicators[:rsi] > 50 && indicators[:rsi] < 70
  score += 10
```

**Required:**
- Take longs when RSI is recovering above 45–50
- Should check for upward momentum, not just static level

**Gap:** Checks static RSI level, not recovery momentum

---

### 5. Reward-to-Risk Ratio

**Current Implementation:**
```ruby
MIN_RR = 2.5  # Minimum risk-reward ratio
```

**Required:**
- Aim ≥ 1:3 on initial setup (e.g., SL at 1× risk, TP near 3×)

**Gap:** Uses 2.5R minimum, but should be 3R minimum per requirements

---

## 📋 DETAILED COMPARISON

### Entry Rules

| Requirement | Current Implementation | Status |
|------------|----------------------|--------|
| Price > 50-DMA and 200-DMA | ✅ Checked in `SetupDetector.bullish?` | ✅ |
| Pullbacks to 20-50 DMA | ✅ `TradePlanBuilder.calculate_entry_price` | ✅ |
| RSI recovering above 45-50 | ⚠️ Checks RSI > 50, not recovery | ⚠️ |
| MACD bullish cross/histogram > 0 | ✅ Checked in scoring | ✅ |
| Supertrend bullish | ✅ Checked in `SetupDetector` | ✅ |

### Stop Loss Rules

| Requirement | Current Implementation | Status |
|------------|----------------------|--------|
| Entry − (ATR × 1.5 to 2.5) | ❌ Fixed 2.0 ATR | ❌ |
| Tighten to 1.5× in calm markets | ❌ Not implemented | ❌ |
| Widen to 2.5–3× in high volatility | ❌ Not implemented | ❌ |
| Position size = Risk ÷ (ATR × multiple) | ✅ Implemented | ✅ |

### Target Rules

| Requirement | Current Implementation | Status |
|------------|----------------------|--------|
| TP1 = Entry + (ATR × 2) | ❌ Uses 2.5R instead | ❌ |
| TP2 = Entry + (ATR × 4) | ❌ Not implemented | ❌ |
| Move stop to breakeven after TP1 | ❌ Not implemented | ❌ |
| Trail by 1–2× ATR | ❌ Uses percentage | ❌ |
| Reward-to-risk ≥ 1:3 | ⚠️ Uses 2.5R (should be 3R) | ⚠️ |

---

## 🔧 REQUIRED FIXES

### Priority 1: Critical Gaps

1. **ATR-based Stop Loss with Volatility Adjustment**
   - File: `app/services/screeners/trade_plan_builder.rb`
   - Change: Dynamic ATR multiplier (1.5-2.5) based on volatility

2. **ATR-based Take Profit (TP1/TP2)**
   - File: `app/services/screeners/trade_plan_builder.rb`
   - Change: TP1 = Entry + (ATR × 2), TP2 = Entry + (ATR × 4)

3. **Breakeven Stop After TP1**
   - File: `app/jobs/strategies/swing/exit_monitor_job.rb`
   - Change: Move stop to breakeven when TP1 is hit

4. **ATR-based Trailing Stop**
   - File: `app/models/position.rb` or exit monitor
   - Change: Trail by 1–2× ATR instead of percentage

### Priority 2: Enhancements

5. **RSI Recovery Check**
   - File: `app/services/screeners/setup_detector.rb`
   - Change: Check for RSI recovering above 45-50 (momentum, not static)

6. **Minimum Risk-Reward 3R**
   - File: `app/services/screeners/trade_plan_builder.rb`
   - Change: MIN_RR from 2.5 to 3.0

---

## 📝 IMPLEMENTATION NOTES

### ATR Volatility Classification
```ruby
# Low volatility: ATR % < 2% → Use 1.5× ATR
# Medium volatility: ATR % 2-5% → Use 2.0× ATR  
# High volatility: ATR % > 5% → Use 2.5-3× ATR
```

### TP1/TP2 Structure
```ruby
{
  tp1: entry_price + (atr * 2),
  tp2: entry_price + (atr * 4),
  breakeven_trigger: :tp1_hit  # Move SL to breakeven after TP1
}
```

### ATR Trailing Stop
```ruby
# Trail by 1-2× ATR on daily closes
trailing_stop = highest_price - (atr * 1.5)  # or 2.0
```

---

## ✅ SUMMARY

**Correctly Implemented:**
- Trend filters (EMA, Supertrend)
- Entry conditions (pullbacks, breakouts)
- Indicator combinations
- Position sizing based on ATR

**Needs Fixing:**
- ❌ ATR stop loss multiplier (should be dynamic 1.5-2.5)
- ❌ Take profit (should use ATR multiples, not R-multiples)
- ❌ TP1/TP2 concept missing
- ❌ Breakeven stop after TP1 missing
- ❌ ATR-based trailing stop missing
- ⚠️ RSI recovery check (needs momentum, not static)
- ⚠️ Minimum RR should be 3R, not 2.5R

**Overall Assessment:** Core strategy is implemented, but stop loss and target management need to be updated to match ATR-based requirements exactly.
