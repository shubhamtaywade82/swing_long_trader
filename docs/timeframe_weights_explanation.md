# Timeframe Weights Explanation

## Overview

Different trading styles require different timeframe weights. This document explains the rationale and implementation.

---

## Swing Trading Weights

### Rationale

**Swing Trading** (holding period: 5-20 days):
- Focuses on **shorter-term moves**
- Needs **precise entry timing**
- Benefits from **intraday confirmation**
- Daily timeframe is **primary** for trend

### Current Weights

| Timeframe | Weight | Purpose |
|-----------|--------|---------|
| **Daily (1D)** | **40%** | Primary timeframe - main trend |
| **Hourly (1H)** | **25%** | Entry timing - when to enter |
| **15min (15M)** | **15%** | Precise entry - exact entry point |
| **Weekly (1W)** | **20%** | Trend context - filter only |

**Total: 100%**

### Why These Weights?

1. **Daily (40%)**: Primary timeframe for swing trading
   - Captures swing moves (5-20 days)
   - Main trend identification
   - Entry/exit signals

2. **Hourly (25%)**: Entry timing
   - Refines entry points
   - Confirms daily signals
   - Provides intraday structure

3. **15min (15%)**: Precise entry
   - Exact entry timing
   - Reduces slippage
   - Confirms intraday momentum

4. **Weekly (20%)**: Trend filter
   - Ensures higher timeframe alignment
   - Filters out counter-trend trades
   - Provides context only

---

## Long-Term Trading Weights

### Rationale

**Long-Term Trading** (holding period: weeks/months):
- Focuses on **major trends**
- Needs **trend context** over timing
- Weekly timeframe is **primary**
- 15m is **not relevant** (too noisy)

### Current Weights

| Timeframe | Weight | Purpose |
|-----------|--------|---------|
| **Weekly (1W)** | **40%** | Primary timeframe - major trend |
| **Daily (1D)** | **35%** | Secondary timeframe - trend confirmation |
| **Hourly (1H)** | **25%** | Entry timing - when to enter |
| **15min (15M)** | **0%** | Not used - too noisy for long-term |

**Total: 100%**

### Why These Weights?

1. **Weekly (40%)**: Primary timeframe for long-term
   - Captures major trends (weeks/months)
   - Main trend identification
   - Trend context

2. **Daily (35%)**: Trend confirmation
   - Confirms weekly trend
   - Entry zone identification
   - Trend strength

3. **Hourly (25%)**: Entry timing only
   - Refines entry points
   - Not for trend identification
   - Entry timing only

4. **15min (0%)**: Not used
   - Too noisy for long-term
   - Not relevant for multi-week holds
   - Excluded from analysis

---

## Comparison

### Swing Trading vs Long-Term

| Aspect | Swing Trading | Long-Term Trading |
|--------|---------------|-------------------|
| **Primary TF** | Daily (40%) | Weekly (40%) |
| **Secondary TF** | Hourly (25%) | Daily (35%) |
| **Entry Timing** | 15min (15%) | Hourly (25%) |
| **Trend Context** | Weekly (20%) | N/A |
| **15m Used?** | ✅ Yes (15%) | ❌ No (0%) |
| **Focus** | Entry timing | Trend context |

---

## Implementation

### Swing Trading

```ruby
# In Swing::MultiTimeframeAnalyzer
weights = {
  w1: 0.2,  # Weekly: 20%
  d1: 0.4,  # Daily: 40% (PRIMARY)
  h1: 0.25, # Hourly: 25%
  m15: 0.15, # 15min: 15%
}
```

### Long-Term Trading

```ruby
# In LongTerm::MultiTimeframeAnalyzer
weights = {
  w1: 0.4,  # Weekly: 40% (PRIMARY)
  d1: 0.35, # Daily: 35%
  h1: 0.25, # Hourly: 25%
  m15: 0.0, # 15min: 0% (NOT USED)
}
```

---

## Usage Examples

### Swing Trading

```ruby
# Automatically uses swing weights
result = Swing::MultiTimeframeAnalyzer.call(
  instrument: instrument,
  include_intraday: true,
)

# Weights: D1(40%), H1(25%), M15(15%), W1(20%)
```

### Long-Term Trading

```ruby
# Uses long-term weights (no 15m)
result = LongTerm::MultiTimeframeAnalyzer.call(
  instrument: instrument,
  include_intraday: true, # Only loads 1h, not 15m
)

# Weights: W1(40%), D1(35%), H1(25%), M15(0%)
```

---

## Configuration

### Override Weights (if needed)

```yaml
# config/algo.yml
swing_trading:
  multi_timeframe:
    weights:
      w1: 0.2
      d1: 0.4
      h1: 0.25
      m15: 0.15

long_term_trading:
  multi_timeframe:
    weights:
      w1: 0.4
      d1: 0.35
      h1: 0.25
      m15: 0.0
```

---

## Summary

✅ **Swing Trading**: More weight to **1d (40%), 1h (25%), 15m (15%)**  
✅ **Long-Term Trading**: More weight to **1w (40%), 1d (35%), 1h (25%)**  
✅ **15m excluded** from long-term analysis  
✅ **Weights optimized** for each trading style  

This ensures each trading style uses the most relevant timeframes! 🎯
