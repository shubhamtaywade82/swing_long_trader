# Complete Technical Analysis Guide

## Overview

This document lists **ALL** technical analysis indicators, strategies, and methods used for trend detection and entry recommendations in the swing trading system.

---

## 1. Technical Indicators

### Trend Indicators

#### 1.1 Exponential Moving Averages (EMA)

**Timeframes**: Calculated on all timeframes (15m, 1h, 1d, 1w)

**Periods Used**:
- **EMA20**: Short-term trend
- **EMA50**: Medium-term trend
- **EMA200**: Long-term trend

**Usage**:
```ruby
# Trend Detection
ema20 > ema50  # Short-term bullish
ema20 > ema200 # Long-term bullish
ema50 > ema200 # Medium-term bullish

# Scoring (40 points total)
- EMA20 > EMA50: 20 points
- EMA20 > EMA200: 20 points
```

**Purpose**:
- Primary trend filter
- Trend alignment confirmation
- Entry signal generation

---

#### 1.2 Supertrend

**Timeframes**: All timeframes (15m, 1h, 1d, 1w)

**Configuration**:
- Period: 10 (default)
- Multiplier: 3.0 (default)

**Usage**:
```ruby
# Trend Direction
supertrend[:direction] == :bullish  # Uptrend
supertrend[:direction] == :bearish # Downtrend

# Scoring (30 points)
- Bullish Supertrend: 30 points
- Bearish Supertrend: 0 points
```

**Purpose**:
- Primary trend direction indicator
- Entry/exit signal generation
- Stop loss placement reference

**Implementation**: `Indicators::Supertrend`

---

### Momentum Indicators

#### 1.3 Relative Strength Index (RSI)

**Timeframes**: All timeframes

**Period**: 14

**Usage**:
```ruby
# Momentum Zones
rsi > 50 && rsi < 70  # Bullish momentum (optimal)
rsi > 40 && rsi < 60  # Moderate momentum
rsi < 30              # Oversold
rsi > 70              # Overbought

# Scoring (30 points)
- RSI 50-70: 30 points
- RSI 40-60: 15 points
```

**Purpose**:
- Momentum confirmation
- Overbought/oversold detection
- Entry timing refinement

---

#### 1.4 MACD (Moving Average Convergence Divergence)

**Timeframes**: All timeframes

**Configuration**:
- Fast Period: 12
- Slow Period: 26
- Signal Period: 9

**Usage**:
```ruby
# MACD Crossover
macd_line > signal_line  # Bullish momentum
macd_line < signal_line  # Bearish momentum

# Scoring (30 points)
- MACD > Signal: 30 points
```

**Purpose**:
- Momentum confirmation
- Trend change detection
- Entry signal generation

---

#### 1.5 ADX (Average Directional Index)

**Timeframes**: All timeframes

**Period**: 14

**Usage**:
```ruby
# Trend Strength
adx > 25  # Strong trend (30 points)
adx > 20  # Moderate trend (15 points)
adx < 20  # Weak/no trend (0 points)

# Scoring (30 points)
- ADX > 25: 30 points
- ADX > 20: 15 points
```

**Purpose**:
- Trend strength measurement
- Filter weak trends
- Entry quality assessment

---

### Volatility Indicators

#### 1.6 ATR (Average True Range)

**Timeframes**: All timeframes

**Period**: 14

**Usage**:
```ruby
# Volatility Measurement
atr_pct = (atr / price * 100)  # Percentage volatility

# Stop Loss Calculation
stop_loss = entry_price - (atr * 2.0)  # 2x ATR below entry

# Take Profit Calculation
take_profit = entry_price + (atr * 3.0)  # 3x ATR above entry

# Entry Price Buffer
entry_buffer = atr * 0.1  # Small buffer for breakout entries
```

**Purpose**:
- Volatility measurement
- Stop loss placement
- Take profit targets
- Entry price refinement

---

#### 1.7 Bollinger Bands

**Timeframes**: All timeframes

**Configuration**:
- Period: 20
- Standard Deviation: 2.0

**Usage**:
```ruby
# Price Position
price > upper_band  # Overbought
price < lower_band  # Oversold
price near middle   # Neutral

# Volatility
band_width = (upper - lower) / middle  # Volatility measure
```

**Purpose**:
- Volatility measurement
- Overbought/oversold zones
- Mean reversion signals

---

### Volume Indicators

#### 1.8 Volume Metrics

**Timeframes**: All timeframes

**Metrics Calculated**:
```ruby
{
  latest: latest_volume,
  average: avg_volume,
  spike_ratio: latest_volume / avg_volume,
}
```

**Usage**:
```ruby
# Volume Confirmation
spike_ratio >= 1.5  # Volume spike (confirms move)
spike_ratio >= 2.0  # Strong volume spike

# Scoring (15 points)
- Volume spike >= 1.5: 15 points
```

**Purpose**:
- Entry confirmation
- Breakout validation
- Trend strength confirmation

---

## 2. Structure Analysis

### 2.1 Swing Highs and Lows

**Timeframes**: All timeframes (primary: Daily, Weekly, 1h)

**Method**: `identify_swing_highs` / `identify_swing_lows`

**Logic**:
```ruby
# Swing High: Higher than 2 candles on each side
candle[i].high > candles[i-2..i-1].high.max &&
candle[i].high > candles[i+1..i+2].high.max

# Swing Low: Lower than 2 candles on each side
candle[i].low < candles[i-2..i-1].low.min &&
candle[i].low < candles[i+1..i+2].low.min
```

**Usage**:
- Support/resistance identification
- Structure validation
- Entry/exit levels

---

### 2.2 Higher Highs / Higher Lows

**Timeframes**: All timeframes

**Method**: `check_higher_highs` / `check_higher_lows`

**Logic**:
```ruby
# Higher Highs: Uptrend structure
swing_highs.last(2).map { |sh| sh[:price] }.reduce(:>)

# Higher Lows: Uptrend structure
swing_lows.last(2).map { |sl| sl[:price] }.reduce(:>)
```

**Purpose**:
- Trend structure validation
- Uptrend confirmation
- Entry quality assessment

---

### 2.3 Trend Strength (Linear Regression)

**Timeframes**: All timeframes

**Method**: `calculate_trend_strength`

**Logic**:
```ruby
# Linear regression slope on last 20 candles
slope = calculate_linear_regression_slope(closes.last(20))
trend_strength = (slope / mean_price * 100)  # Percentage
```

**Purpose**:
- Quantitative trend strength
- Trend quality measurement
- Entry confidence boost

---

## 3. Support and Resistance

### 3.1 Support Levels

**Sources**:
- **Weekly**: Major support levels (long-term)
- **Daily**: Primary support levels (medium-term)
- **1h**: Intraday support levels (short-term)

**Identification**:
```ruby
# From swing lows
support_levels = swing_lows.map { |sl| sl[:price] }
# Top 5 support levels (sorted descending)
```

**Usage**:
- Entry zone identification
- Stop loss placement
- Pullback entry detection

---

### 3.2 Resistance Levels

**Sources**:
- **Weekly**: Major resistance levels (long-term)
- **Daily**: Primary resistance levels (medium-term)
- **1h**: Intraday resistance levels (short-term)

**Identification**:
```ruby
# From swing highs
resistance_levels = swing_highs.map { |sh| sh[:price] }
# Top 5 resistance levels (sorted ascending)
```

**Usage**:
- Take profit targets
- Breakout entry identification
- Exit signal generation

---

## 4. Smart Money Concepts (SMC)

### 4.1 BOS (Break of Structure)

**File**: `app/services/smc/bos.rb`

**Purpose**:
- Identifies structural breaks
- Confirms trend changes
- Validates entry signals

**Usage**:
```ruby
# Validates if price breaks previous structure
Smc::Bos.validate(candles, direction: :long)
```

---

### 4.2 CHoCH (Change of Character)

**File**: `app/services/smc/choch.rb`

**Purpose**:
- Detects trend character changes
- Identifies potential reversals
- Confirms structure breaks

---

### 4.3 Order Blocks

**File**: `app/services/smc/order_block.rb`

**Purpose**:
- Identifies institutional order zones
- Entry zone refinement
- High-probability entry areas

**Logic**:
```ruby
# Order block: Last bullish candle before bearish move
# Minimum body ratio: 60% of candle
```

---

### 4.4 Fair Value Gap (FVG)

**File**: `app/services/smc/fair_value_gap.rb`

**Purpose**:
- Identifies price gaps
- Entry zone identification
- Price target zones

---

### 4.5 Mitigation Blocks

**File**: `app/services/smc/mitigation_block.rb`

**Purpose**:
- Identifies mitigation zones
- Support/resistance refinement
- Entry timing

---

### 4.6 Structure Validator

**File**: `app/services/smc/structure_validator.rb`

**Purpose**:
- Validates overall SMC structure
- Entry signal confirmation
- Trend validation

**Usage**:
```ruby
Smc::StructureValidator.validate(
  candles,
  direction: :long,
  config: smc_config,
)
```

---

## 5. Multi-Timeframe Analysis

### 5.1 Timeframe Hierarchy

```
Weekly (1W)  → Trend Context & Major S/R
    ↓
Daily (1D)   → Primary Analysis & Entry Signals
    ↓
Hourly (1H)  → Entry Timing & Intraday Structure
    ↓
15min (15M)  → Precise Entry & Exit Timing
```

---

### 5.2 Trend Alignment

**Method**: `analyze_trend_alignment`

**Logic**:
```ruby
# Check trend direction across all timeframes
directions = [m15, h1, d1, w1].map { |tf| tf[:trend_direction] }

# Alignment: Majority bullish
bullish_count > bearish_count &&
bullish_count >= (total_timeframes / 2.0).ceil
```

**Scoring**:
- All 4 timeframes bullish: Excellent alignment
- 3/4 timeframes bullish: Good alignment
- 2/4 timeframes bullish: Fair alignment
- <2/4 timeframes bullish: Poor alignment

---

### 5.3 Momentum Alignment

**Method**: `analyze_momentum_alignment`

**Logic**:
```ruby
# Check momentum direction across all timeframes
momentum_directions = [m15, h1, d1, w1].map { |tf| tf[:momentum_direction] }

# Alignment: Majority bullish momentum
bullish_count > bearish_count
```

**Usage**:
- Entry timing confirmation
- Confidence boost (+10 points)
- Entry quality assessment

---

### 5.4 Multi-Timeframe Score

**Method**: `calculate_mtf_score`

**Weighting**:
- Weekly (1W): 30%
- Daily (1D): 40%
- Hourly (1H): 20%
- 15min (15M): 10%

**Calculation**:
```ruby
# Per timeframe: Trend (60%) + Momentum (40%)
combined_score = (trend_score * 0.6 + momentum_score * 0.4)

# Weighted average across timeframes
mtf_score = Σ(combined_score * weight) / Σ(weight)
```

---

## 6. Entry Recommendation Strategies

### 6.1 Support Bounce Entry

**Conditions**:
1. ✅ Trend aligned across timeframes
2. ✅ Price above nearest support
3. ✅ Within 3% of support level
4. ✅ 1h/15m confirm bullish (optional boost)

**Entry Zone**:
```ruby
entry_zone = [nearest_support, current_price]
# Refined by 15m close if available
```

**Stop Loss**:
```ruby
stop_loss = nearest_support * 0.98  # 2% below support
```

**Confidence Boost**:
- Base confidence: MTF score
- +10 if momentum aligned
- +5 if 1h bullish
- +5 if 15m bullish

---

### 6.2 Breakout Entry

**Conditions**:
1. ✅ Trend aligned across timeframes
2. ✅ Price near resistance (within 2%)
3. ✅ 1h/15m confirm breakout (optional boost)

**Entry Zone**:
```ruby
entry_zone = [current_price, resistance * 1.01]
# Refined by 15m close if above current
```

**Stop Loss**:
```ruby
stop_loss = entry_price * 0.97  # 3% below entry
```

**Confidence Boost**:
- Same as support bounce
- Additional boost if 15m confirms breakout

---

### 6.3 Intraday Pullback Entry (NEW)

**Conditions**:
1. ✅ Daily/Weekly trend bullish
2. ✅ 1h/15m show pullback (momentum neutral)
3. ✅ Price near 1h support
4. ✅ Trend still bullish on intraday

**Entry Zone**:
```ruby
entry_zone = [1h_support, current_price]
```

**Stop Loss**:
```ruby
stop_loss = 1h_support * 0.99  # 1% below 1h support
```

**Purpose**:
- Enter on intraday pullbacks
- Better entry prices
- Lower risk entries

---

## 7. Scoring System

### 7.1 Trend Score (Per Timeframe)

**Total: 100 points**

| Component | Points | Condition |
|-----------|--------|-----------|
| EMA20 > EMA50 | 20 | Short-term bullish |
| EMA20 > EMA200 | 20 | Long-term bullish |
| Supertrend Bullish | 30 | Trend direction |
| ADX > 25 | 30 | Strong trend |
| ADX > 20 | 15 | Moderate trend |

---

### 7.2 Momentum Score (Per Timeframe)

**Total: 100 points**

| Component | Points | Condition |
|-----------|--------|-----------|
| RSI 50-70 | 30 | Optimal momentum |
| RSI 40-60 | 15 | Moderate momentum |
| MACD > Signal | 30 | Bullish crossover |
| Price Change 5-period | 40 | Positive momentum |

---

### 7.3 Combined Score

**Calculation**:
```ruby
# Per timeframe
combined_score = (trend_score * 0.6) + (momentum_score * 0.4)

# Multi-timeframe weighted average
mtf_score = Σ(combined_score * weight) / Σ(weight)
```

**Final Score**:
```ruby
# Base score (daily-only): 60%
# MTF score: 40%
final_score = (base_score * 0.6) + (mtf_score * 0.4)
```

---

## 8. Entry Signal Generation

### 8.1 Direction Determination

**Primary Method**: Multi-Timeframe Trend Alignment
```ruby
if mtf_analysis[:trend_alignment][:aligned]
  return :long if bullish_count > bearish_count
end
```

**Fallback Method**: Daily Supertrend + EMA
```ruby
if supertrend[:direction] == :bullish &&
   ema20 > ema50 &&
   ema20 > ema200
  return :long
end
```

---

### 8.2 Entry Price Calculation

**Method 1**: MTF Entry Recommendations (Preferred)
```ruby
# Use highest confidence recommendation
# Prefer entries with 15m/1h confirmation
entry_price = calculate_entry_from_mtf(mtf_analysis, direction)
```

**Method 2**: ATR-Based Breakout
```ruby
# Long entry
recent_high = candles.last(20).map(&:high).max
entry = [recent_high, current_close].max
entry += (atr * 0.1)  # Small buffer
```

**Method 3**: Support Retest
```ruby
# Entry near support
entry = nearest_support + (atr * 0.05)  # Slightly above support
```

---

### 8.3 Stop Loss Calculation

**Method 1**: MTF Support-Based (Preferred)
```ruby
# Use nearest support from MTF analysis
stop_loss = nearest_support * 0.98  # 2% below support
```

**Method 2**: ATR-Based
```ruby
stop_loss = entry_price - (atr * 2.0)  # 2x ATR
```

**Method 3**: Percentage-Based
```ruby
stop_loss = entry_price * (1 - stop_loss_pct / 100.0)  # Default 8%
```

**Final**: Minimum of all methods
```ruby
stop_loss = [support_based, atr_based, pct_based].min
```

---

### 8.4 Take Profit Calculation

**Method 1**: MTF Resistance-Based (Preferred)
```ruby
# Use nearest resistance from MTF analysis
take_profit = nearest_resistance * 0.99  # Slightly below resistance
```

**Method 2**: Risk-Reward Based
```ruby
risk = entry_price - stop_loss
take_profit = entry_price + (risk * 2.25)  # 2.25x RR
```

**Method 3**: ATR-Based
```ruby
take_profit = entry_price + (atr * 3.0)  # 3x ATR
```

**Method 4**: Percentage-Based
```ruby
take_profit = entry_price * (1 + profit_target_pct / 100.0)  # Default 15%
```

**Final**: Minimum of all methods (for longs)
```ruby
take_profit = [resistance_based, rr_based, atr_based, pct_based].min
```

---

## 9. Confidence Calculation

### 9.1 Base Confidence (Daily Timeframe)

**Total: 60 points**

| Component | Points | Condition |
|-----------|--------|-----------|
| EMA20 > EMA50 | 15 | Short-term trend |
| EMA20 > EMA200 | 15 | Long-term trend |
| Supertrend Bullish | 20 | Trend direction |
| ADX > 25 | 20 | Strong trend |
| ADX > 20 | 10 | Moderate trend |
| RSI 50-70 | 15 | Optimal momentum |
| RSI 40-60 | 8 | Moderate momentum |
| MACD > Signal | 15 | Bullish crossover |

---

### 9.2 MTF Boost

**Total: 40 points**

| Component | Points | Condition |
|-----------|--------|-----------|
| Trend Alignment | Up to 20 | Based on alignment % |
| Momentum Alignment | 10 | If aligned |
| MTF Score | Up to 10 | 10% of MTF score |

---

### 9.3 Final Confidence

```ruby
confidence = base_confidence + mtf_boost
confidence = [confidence, 100].min  # Cap at 100
```

---

## 10. Complete Analysis Flow

### Step-by-Step Process

```
1. Load Candles
   ├─ 15m: 2 days (on-demand)
   ├─ 1h: 5 days (on-demand)
   ├─ 1d: 200 candles (database)
   └─ 1w: 52 candles (database)

2. Calculate Indicators (Per Timeframe)
   ├─ EMA (20, 50, 200)
   ├─ RSI (14)
   ├─ ADX (14)
   ├─ ATR (14)
   ├─ MACD (12, 26, 9)
   ├─ Supertrend (10, 3.0)
   ├─ Bollinger Bands (20, 2.0)
   └─ Volume Metrics

3. Structure Analysis (Per Timeframe)
   ├─ Swing Highs/Lows
   ├─ Higher Highs/Higher Lows
   └─ Trend Strength (Linear Regression)

4. Support/Resistance Identification
   ├─ Weekly: Major levels
   ├─ Daily: Primary levels
   └─ 1h: Intraday levels

5. Trend Alignment Analysis
   ├─ Check all timeframes
   ├─ Count bullish/bearish
   └─ Determine alignment

6. Momentum Alignment Analysis
   ├─ Check all timeframes
   ├─ Count bullish/bearish momentum
   └─ Determine alignment

7. Multi-Timeframe Score
   ├─ Calculate per timeframe
   ├─ Weight by importance
   └─ Combine scores

8. Entry Recommendations
   ├─ Support Bounce
   ├─ Breakout
   └─ Intraday Pullback

9. Signal Generation
   ├─ Direction determination
   ├─ Entry price calculation
   ├─ Stop loss calculation
   ├─ Take profit calculation
   └─ Confidence calculation

10. AI Evaluation (Optional)
    ├─ Send MTF data to OpenAI
    ├─ Get AI score/confidence
    └─ Timeframe alignment assessment
```

---

## 11. Indicator Configuration

### Default Parameters

```yaml
# config/algo.yml
indicators:
  supertrend:
    period: 10
    multiplier: 3.0
  
  ema:
    short: 20
    medium: 50
    long: 200
  
  rsi:
    period: 14
  
  adx:
    period: 14
  
  atr:
    period: 14
  
  macd:
    fast: 12
    slow: 26
    signal: 9
  
  bollinger:
    period: 20
    std_dev: 2.0
```

---

## 12. Strategy Rules

### Entry Rules

1. **Trend Alignment**: Majority of timeframes bullish
2. **Momentum Alignment**: Majority momentum bullish
3. **Supertrend**: Bullish on daily timeframe
4. **EMA Alignment**: EMA20 > EMA50 > EMA200 (preferred)
5. **ADX**: > 20 (moderate trend), > 25 (strong trend)
6. **RSI**: 50-70 (optimal), 40-60 (acceptable)
7. **Volume**: Spike ratio >= 1.5 (if required)
8. **SMC Structure**: Valid (if SMC enabled)

---

### Exit Rules

1. **Take Profit**: Hit target (resistance-based or RR-based)
2. **Stop Loss**: Hit stop (support-based or ATR-based)
3. **Supertrend Flip**: Supertrend turns bearish
4. **EMA Crossover**: EMA20 crosses below EMA50
5. **Structure Break**: Break of structure (SMC)
6. **Time-Based**: Holding period exceeded

---

## 13. Summary Table

| Category | Indicators/Methods | Timeframes | Purpose |
|----------|-------------------|------------|---------|
| **Trend** | EMA (20, 50, 200) | All | Trend direction |
| **Trend** | Supertrend | All | Trend direction |
| **Trend** | ADX | All | Trend strength |
| **Momentum** | RSI | All | Momentum |
| **Momentum** | MACD | All | Momentum |
| **Momentum** | Price Change | All | Momentum |
| **Volatility** | ATR | All | Stop loss/TP |
| **Volatility** | Bollinger Bands | All | Volatility zones |
| **Volume** | Volume Spike | All | Confirmation |
| **Structure** | Swing Highs/Lows | All | S/R levels |
| **Structure** | Higher Highs/Lows | All | Trend structure |
| **Structure** | Trend Strength | All | Quantitative trend |
| **SMC** | BOS | Daily | Structure breaks |
| **SMC** | CHoCH | Daily | Character changes |
| **SMC** | Order Blocks | Daily | Entry zones |
| **SMC** | FVG | Daily | Price gaps |
| **SMC** | Mitigation Blocks | Daily | Support zones |
| **MTF** | Trend Alignment | All | Multi-TF confirmation |
| **MTF** | Momentum Alignment | All | Multi-TF momentum |
| **MTF** | MTF Score | All | Combined score |

---

## 14. Complete Indicator List

### Calculated on ALL Timeframes (15m, 1h, 1d, 1w)

1. ✅ EMA20
2. ✅ EMA50
3. ✅ EMA200
4. ✅ RSI (14)
5. ✅ ADX (14)
6. ✅ ATR (14)
7. ✅ MACD (12, 26, 9)
8. ✅ Supertrend (10, 3.0)
9. ✅ Bollinger Bands (20, 2.0)
10. ✅ Volume Metrics (spike ratio)

### Structure Analysis

11. ✅ Swing Highs
12. ✅ Swing Lows
13. ✅ Higher Highs
14. ✅ Higher Lows
15. ✅ Trend Strength (Linear Regression)

### Smart Money Concepts

16. ✅ BOS (Break of Structure)
17. ✅ CHoCH (Change of Character)
18. ✅ Order Blocks
19. ✅ Fair Value Gap
20. ✅ Mitigation Blocks

### Multi-Timeframe Analysis

21. ✅ Trend Alignment
22. ✅ Momentum Alignment
23. ✅ Multi-Timeframe Score
24. ✅ Support/Resistance (from multiple TFs)

---

## 15. Entry Recommendation Types

1. **Support Bounce**: Entry near support with intraday confirmation
2. **Breakout**: Entry near resistance with breakout confirmation
3. **Intraday Pullback**: Entry on 1h/15m pullback while daily/weekly bullish

---

## Summary

The system uses **24+ technical indicators and analysis methods** across **4 timeframes** (15m, 1h, 1d, 1w) to:

✅ **Detect Trends**: EMA, Supertrend, ADX, Structure  
✅ **Measure Momentum**: RSI, MACD, Price Change  
✅ **Assess Volatility**: ATR, Bollinger Bands  
✅ **Identify Structure**: Swing Highs/Lows, Higher Highs/Lows  
✅ **Find S/R Levels**: Multi-timeframe support/resistance  
✅ **Generate Entries**: Support bounce, Breakout, Pullback  
✅ **Calculate Confidence**: Base + MTF boost  

This creates a **comprehensive, institutional-grade technical analysis system**! 🚀
