# Intraday Timeframes (15m, 1h) Usage in Swing Trading

## Overview

Yes, **15m and 1h timeframes ARE used** in swing trading! They play a crucial role in entry timing and confirmation.

---

## How 15m and 1h Are Used

### 1. Multi-Timeframe Score Calculation

**Weighting:**
- Weekly (1W): 30%
- Daily (1D): 40%
- **Hourly (1H): 20%** ← Used!
- **15min (15M): 10%** ← Used!

Both intraday timeframes contribute to the overall MTF score.

---

### 2. Trend Alignment Analysis

**All 4 timeframes** (15m, 1h, 1d, 1w) are checked for trend alignment:

```ruby
# From MultiTimeframeAnalyzer
def analyze_trend_alignment(timeframes)
  directions = timeframes.values.map { |tf| tf[:trend_direction] }
  # Includes m15, h1, d1, w1 directions
  bullish_count = directions.count(:bullish)
  # Alignment requires majority bullish across ALL timeframes
end
```

**Example:**
- Weekly: Bullish ✅
- Daily: Bullish ✅
- **1h: Bullish ✅** ← Confirms
- **15m: Bullish ✅** ← Confirms
- **Result: Excellent alignment (4/4)**

---

### 3. Momentum Alignment

**All timeframes** checked for momentum:

```ruby
def analyze_momentum_alignment(timeframes)
  directions = timeframes.values.map { |tf| tf[:momentum_direction] }
  # Includes momentum from 15m, 1h, 1d, 1w
end
```

---

### 4. Entry Timing Confirmation

**15m and 1h are used to confirm entry timing:**

```ruby
# From generate_entry_recommendations
h1_bullish = h1_tf[:trend_direction] == :bullish && 
             h1_tf[:momentum_direction] == :bullish

m15_bullish = m15_tf[:trend_direction] == :bullish && 
              m15_tf[:momentum_direction] == :bullish

# Boost confidence if intraday confirms
entry_confidence += 5 if h1_bullish  # +5% if 1h confirms
entry_confidence += 5 if m15_bullish # +5% if 15m confirms
```

---

### 5. Precise Entry Zone Calculation

**15m and 1h used for precise entry zones:**

```ruby
# For support bounce entries
if m15_tf && m15_tf[:latest_close]
  # Use 15m close as upper bound for entry zone
  entry_zone_high = [current_price, m15_tf[:latest_close]].max
end

# For breakout entries
if m15_tf && m15_tf[:latest_close] > current_price
  # Use 15m close if it's above current (breakout confirmation)
  entry_zone_low = [current_price, m15_tf[:latest_close]].min
end
```

---

### 6. Intraday Support/Resistance

**1h timeframe provides intraday S/R levels:**

```ruby
# From identify_support_resistance
if h1_tf && h1_tf[:structure][:swing_lows]&.any?
  h1_supports = h1_tf[:structure][:swing_lows].map { |sl| sl[:price] }
  support_levels += h1_supports.last(3) # Last 3 swing lows from 1h
end
```

These are used for:
- Entry timing near intraday support
- Stop loss placement
- Pullback entry identification

---

### 7. Intraday Pullback Entries

**New entry type that uses 15m/1h:**

```ruby
# Detect pullback on intraday while daily/weekly remain bullish
h1_pullback = h1_tf[:trend_direction] == :bullish && 
              h1_tf[:momentum_direction] == :neutral

m15_pullback = m15_tf[:trend_direction] == :bullish && 
               m15_tf[:momentum_direction] == :neutral

if h1_pullback || m15_pullback
  # Entry on intraday pullback to 1h support
  recommendations << {
    type: :intraday_pullback,
    entry_zone: [h1_support, current_price],
    stop_loss: h1_support * 0.99,
    timeframe: h1_pullback ? "1h" : "15m",
  }
end
```

---

## Entry Recommendation Types

### 1. Support Bounce (Enhanced with Intraday)

**Uses:**
- Daily/Weekly: Support level identification
- **1h: Entry timing confirmation**
- **15m: Precise entry zone**

**Example:**
```ruby
{
  type: :support_bounce,
  entry_zone: [2450, 2460],  # 15m helps refine this
  stop_loss: 2401,
  confidence: 85,  # +5 if 1h confirms, +5 if 15m confirms
  intraday_confirmation: {
    h1_bullish: true,
    m15_bullish: true,
  },
}
```

---

### 2. Breakout (Enhanced with Intraday)

**Uses:**
- Daily/Weekly: Resistance level
- **1h: Breakout confirmation**
- **15m: Precise entry timing**

**Example:**
```ruby
{
  type: :breakout,
  entry_zone: [2500, 2525],  # 15m close helps refine
  stop_loss: 2425,
  confidence: 90,  # Enhanced with intraday confirmation
  intraday_confirmation: {
    h1_bullish: true,
    m15_bullish: true,
  },
}
```

---

### 3. Intraday Pullback (NEW - Uses 15m/1h)

**Uses:**
- **1h: Pullback detection and support level**
- **15m: Entry timing**
- Daily/Weekly: Trend context (must be bullish)

**Example:**
```ruby
{
  type: :intraday_pullback,
  entry_zone: [2460, 2470],  # Near 1h support
  stop_loss: 2435,  # Just below 1h support
  confidence: 75,
  intraday_confirmation: {
    h1_pullback: true,
    m15_pullback: true,
    timeframe: "1h",
  },
}
```

---

## Signal Builder Usage

### Entry Price Calculation

**SignalBuilder prioritizes intraday-confirmed entries:**

```ruby
def calculate_entry_from_mtf(mtf_analysis, direction)
  recommendations = mtf_analysis[:entry_recommendations]
  
  # Prefer entries with 15m confirmation
  best_rec = recommendations.find { |r| r[:intraday_confirmation]&.dig(:m15_bullish) } ||
             # Fallback to 1h confirmation
             recommendations.find { |r| r[:intraday_confirmation]&.dig(:h1_bullish) } ||
             # Default to highest confidence
             recommendations.first
  
  # Use entry zone (refined by 15m/1h)
  entry_zone = best_rec[:entry_zone]
end
```

---

## Testing Intraday Usage

### Verify 15m/1h Are Loaded

```ruby
# Rails console
result = Swing::MultiTimeframeAnalyzer.call(
  instrument: Instrument.find_by(symbol_name: "RELIANCE"),
  include_intraday: true,
)

analysis = result[:analysis]
puts "Timeframes analyzed: #{analysis[:timeframes].keys}"
# Should show: [:m15, :h1, :d1, :w1]
```

### Check Intraday Data

```ruby
m15_tf = analysis[:timeframes][:m15]
h1_tf = analysis[:timeframes][:h1]

puts "15m candles: #{m15_tf[:candles_count]}"
puts "15m trend: #{m15_tf[:trend_direction]}"
puts "15m momentum: #{m15_tf[:momentum_direction]}"

puts "1h candles: #{h1_tf[:candles_count]}"
puts "1h trend: #{h1_tf[:trend_direction]}"
puts "1h momentum: #{h1_tf[:momentum_direction]}"
```

### Check Entry Recommendations

```ruby
recommendations = analysis[:entry_recommendations]
recommendations.each do |rec|
  puts "Type: #{rec[:type]}"
  puts "Confidence: #{rec[:confidence]}"
  puts "Intraday Confirmation:"
  puts "  - 1h Bullish: #{rec[:intraday_confirmation][:h1_bullish]}"
  puts "  - 15m Bullish: #{rec[:intraday_confirmation][:m15_bullish]}"
end
```

---

## Configuration

### Enable/Disable Intraday

**Default: Enabled**
```yaml
# config/algo.yml
swing_trading:
  multi_timeframe:
    include_intraday: true  # Set false to disable 15m/1h
```

**In Code:**
```ruby
# Include intraday (default)
Swing::MultiTimeframeAnalyzer.call(instrument: instrument, include_intraday: true)

# Exclude intraday (daily/weekly only)
Swing::MultiTimeframeAnalyzer.call(instrument: instrument, include_intraday: false)
```

---

## Summary

✅ **15m and 1h ARE used** in swing trading for:

1. ✅ **MTF Score**: 15m (10%), 1h (20%) weighted contribution
2. ✅ **Trend Alignment**: All 4 timeframes checked
3. ✅ **Momentum Alignment**: All 4 timeframes checked
4. ✅ **Entry Timing**: 15m/1h confirm entry timing (+5% confidence each)
5. ✅ **Entry Zone**: 15m close used for precise entry zones
6. ✅ **Intraday S/R**: 1h provides intraday support/resistance levels
7. ✅ **Pullback Entries**: New entry type using 15m/1h pullbacks
8. ✅ **Signal Priority**: Entries with intraday confirmation prioritized

**15m and 1h are actively used** for entry timing and confirmation! 🎯
