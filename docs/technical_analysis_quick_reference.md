# Technical Analysis Quick Reference

## All Indicators & Strategies Used

### 📊 Technical Indicators (10)

| Indicator | Period | Timeframes | Purpose |
|-----------|--------|------------|---------|
| **EMA20** | 20 | All (15m,1h,1d,1w) | Short-term trend |
| **EMA50** | 50 | All | Medium-term trend |
| **EMA200** | 200 | All | Long-term trend |
| **RSI** | 14 | All | Momentum (50-70 optimal) |
| **ADX** | 14 | All | Trend strength (>25 strong) |
| **ATR** | 14 | All | Volatility (for SL/TP) |
| **MACD** | 12,26,9 | All | Momentum crossover |
| **Supertrend** | 10,3.0 | All | Trend direction |
| **Bollinger Bands** | 20,2.0 | All | Volatility zones |
| **Volume Spike** | N/A | All | Confirmation (≥1.5x) |

---

### 🏗️ Structure Analysis (5)

| Method | Timeframes | Purpose |
|--------|------------|---------|
| **Swing Highs** | All | Resistance levels |
| **Swing Lows** | All | Support levels |
| **Higher Highs** | All | Uptrend structure |
| **Higher Lows** | All | Uptrend structure |
| **Trend Strength** | All | Linear regression slope |

---

### 💰 Smart Money Concepts (5)

| Concept | File | Purpose |
|---------|------|---------|
| **BOS** | `smc/bos.rb` | Break of Structure |
| **CHoCH** | `smc/choch.rb` | Change of Character |
| **Order Blocks** | `smc/order_block.rb` | Institutional zones |
| **Fair Value Gap** | `smc/fair_value_gap.rb` | Price gaps |
| **Mitigation Blocks** | `smc/mitigation_block.rb` | Support zones |

---

### 🎯 Entry Strategies (3)

| Strategy | Conditions | Entry Zone |
|----------|------------|------------|
| **Support Bounce** | Price near support, trend aligned | [Support, Current] |
| **Breakout** | Price near resistance, trend aligned | [Current, Resistance] |
| **Intraday Pullback** | 1h/15m pullback, daily/weekly bullish | [1h Support, Current] |

---

### 📈 Trend Detection Methods

1. **Multi-Timeframe Alignment**
   - Check trend direction on 15m, 1h, 1d, 1w
   - Require majority bullish

2. **EMA Alignment**
   - EMA20 > EMA50 > EMA200 (bullish)
   - Checked on all timeframes

3. **Supertrend**
   - Primary trend indicator
   - Bullish = uptrend

4. **ADX Strength**
   - ADX > 25 = Strong trend
   - ADX > 20 = Moderate trend

5. **Structure Analysis**
   - Higher highs + Higher lows = Uptrend
   - Validated across timeframes

---

### ⚡ Momentum Detection Methods

1. **RSI Momentum**
   - 50-70 = Optimal bullish momentum
   - 40-60 = Moderate momentum

2. **MACD Crossover**
   - MACD line > Signal line = Bullish momentum

3. **Price Change**
   - 5-period change > 2% = Bullish momentum

4. **Multi-Timeframe Momentum**
   - Check momentum on all timeframes
   - Require majority bullish

---

### 🎯 Entry Recommendation Logic

**Step 1: Trend Filter**
```ruby
# Must have trend alignment
trend_aligned = bullish_count > bearish_count
```

**Step 2: Support/Resistance Identification**
```ruby
# From weekly, daily, 1h swing highs/lows
support_levels = [weekly_lows, daily_lows, 1h_lows].flatten
resistance_levels = [weekly_highs, daily_highs, 1h_highs].flatten
```

**Step 3: Entry Zone Calculation**
```ruby
# Support Bounce
if price near support && trend_aligned
  entry_zone = [support, current_price]
  # Refined by 15m close
end

# Breakout
if price near resistance && trend_aligned
  entry_zone = [current_price, resistance * 1.01]
  # Refined by 15m breakout confirmation
end

# Intraday Pullback
if 1h/15m pullback && daily/weekly bullish
  entry_zone = [1h_support, current_price]
end
```

**Step 4: Confidence Boost**
```ruby
confidence = base_score
confidence += 10 if momentum_aligned
confidence += 5 if 1h_bullish
confidence += 5 if 15m_bullish
```

---

### 📊 Scoring Breakdown

**Trend Score (100 points)**:
- EMA alignment: 40 points
- Supertrend: 30 points
- ADX strength: 30 points

**Momentum Score (100 points)**:
- RSI: 30 points
- MACD: 30 points
- Price change: 40 points

**Combined Score**:
- Trend (60%) + Momentum (40%) = Per-Timeframe Score
- Weighted average across timeframes = MTF Score

**Final Score**:
- Base Score (60%) + MTF Score (40%) = Final Score

---

## Complete Analysis Checklist

### ✅ Trend Detection
- [ ] EMA20 > EMA50 > EMA200
- [ ] Supertrend bullish
- [ ] ADX > 20 (moderate) or > 25 (strong)
- [ ] Higher highs + Higher lows
- [ ] Multi-timeframe alignment (majority bullish)

### ✅ Momentum Confirmation
- [ ] RSI 50-70 (optimal) or 40-60 (moderate)
- [ ] MACD > Signal line
- [ ] Positive 5-period price change
- [ ] Multi-timeframe momentum alignment

### ✅ Structure Validation
- [ ] Swing highs/lows identified
- [ ] Support/resistance levels mapped
- [ ] SMC structure valid (if enabled)
- [ ] Trend strength positive

### ✅ Entry Setup
- [ ] Price near support (bounce) OR resistance (breakout)
- [ ] 1h/15m confirm entry timing
- [ ] Volume spike (if required)
- [ ] Risk-reward ratio ≥ 1.5

---

## Summary

**Total Analysis Methods**: 24+

**Categories**:
- ✅ 10 Technical Indicators
- ✅ 5 Structure Analysis Methods
- ✅ 5 Smart Money Concepts
- ✅ 3 Entry Strategies
- ✅ 1 Multi-Timeframe Analysis System

**Timeframes Analyzed**: 15m, 1h, 1d, 1w

**Purpose**: Comprehensive trend detection and entry recommendation system! 🚀
