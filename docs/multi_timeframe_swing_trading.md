# Multi-Timeframe Swing Trading System

## Overview

The swing trading system now uses **multiple timeframes (15m, 1h, 1d, 1w)** for comprehensive analysis, signal generation, and entry recommendations. This creates a professional-grade multi-timeframe trading system integrated with OpenAI evaluations.

---

## Architecture

### Timeframe Hierarchy

```
Weekly (1W)  → Trend Context & Major Support/Resistance
    ↓
Daily (1D)   → Primary Analysis & Entry Signals
    ↓
Hourly (1H)  → Entry Timing & Intraday Structure
    ↓
15min (15M)  → Precise Entry & Exit Timing
```

### Component Flow

```
Instrument
    ↓
MultiTimeframeAnalyzer
    ├─ Loads 15m, 1h, 1d, 1w candles
    ├─ Calculates indicators per timeframe
    ├─ Analyzes trend alignment
    ├─ Identifies support/resistance
    └─ Generates entry recommendations
    ↓
SwingScreener / SignalBuilder
    ├─ Uses MTF analysis for scoring
    ├─ Enhances confidence with MTF alignment
    └─ Uses MTF S/R for stop loss/take profit
    ↓
AI Evaluator / AI Ranker
    ├─ Receives MTF data in prompts
    ├─ Evaluates timeframe alignment
    └─ Provides MTF-aware recommendations
```

---

## Components

### 1. MultiTimeframeAnalyzer (`app/services/swing/multi_timeframe_analyzer.rb`)

**Purpose**: Loads and analyzes all supported timeframes for an instrument.

**Key Features**:
- Loads 15m, 1h, 1d, 1w candles (intraday on-demand, daily/weekly from DB)
- Calculates indicators per timeframe (EMA, RSI, ADX, ATR, MACD, Supertrend)
- Analyzes trend alignment across timeframes
- Identifies support/resistance levels
- Generates entry recommendations based on MTF structure

**Output Structure**:
```ruby
{
  success: true,
  analysis: {
    instrument_id: 123,
    symbol: "RELIANCE",
    timeframes: {
      m15: { trend_score: 75, momentum_score: 80, ... },
      h1: { trend_score: 80, momentum_score: 75, ... },
      d1: { trend_score: 85, momentum_score: 70, ... },
      w1: { trend_score: 90, momentum_score: 65, ... },
    },
    multi_timeframe_score: 82.5,
    trend_alignment: {
      bullish_count: 3,
      bearish_count: 1,
      aligned: true,
    },
    momentum_alignment: {
      bullish_count: 2,
      bearish_count: 2,
      aligned: true,
    },
    support_resistance: {
      support_levels: [2450, 2420, 2400],
      resistance_levels: [2500, 2520, 2550],
    },
    entry_recommendations: [
      {
        type: :support_bounce,
        entry_zone: [2450, 2460],
        stop_loss: 2401,
        confidence: 85,
      },
    ],
  },
}
```

---

### 2. Updated SwingScreener

**Changes**:
- Calls `MultiTimeframeAnalyzer` for each instrument
- Combines base score (60%) with MTF score (40%)
- Includes MTF metadata in candidate output

**Example Output**:
```ruby
{
  instrument_id: 123,
  symbol: "RELIANCE",
  score: 82.5,           # Combined score
  base_score: 80.0,      # Daily-only score
  mtf_score: 85.0,      # Multi-timeframe score
  indicators: { ... },
  multi_timeframe: { ... },
  metadata: {
    multi_timeframe: {
      score: 85.0,
      trend_alignment: { aligned: true, ... },
      entry_recommendations: [ ... ],
    },
  },
}
```

---

### 3. Updated SignalBuilder

**Changes**:
- Uses MTF analysis for direction determination
- Uses MTF support/resistance for stop loss placement
- Uses MTF resistance levels for take profit targets
- Enhances confidence with MTF alignment scores
- Uses MTF entry recommendations when available

**Key Enhancements**:

1. **Direction Determination**:
   ```ruby
   # Prioritizes MTF trend alignment
   if mtf_analysis[:trend_alignment][:aligned]
     return :long if bullish_count > bearish_count
   end
   ```

2. **Stop Loss Calculation**:
   ```ruby
   # Uses MTF support levels
   if mtf_analysis[:support_resistance][:support_levels].any?
     nearest_support = support_levels.first
     stop_loss = nearest_support * 0.98  # 2% below support
   end
   ```

3. **Take Profit Calculation**:
   ```ruby
   # Uses MTF resistance levels
   if mtf_analysis[:support_resistance][:resistance_levels].any?
     nearest_resistance = resistance_levels.first
     take_profit = nearest_resistance * 0.99  # Slightly below resistance
   end
   ```

4. **Confidence Enhancement**:
   ```ruby
   # Base confidence from daily (60 points)
   confidence = calculate_daily_confidence()
   
   # MTF boost (40 points)
   if mtf_analysis[:trend_alignment][:aligned]
     confidence += 20
   end
   if mtf_analysis[:momentum_alignment][:aligned]
     confidence += 10
   end
   confidence += mtf_score * 0.1  # Up to 10 points
   ```

---

### 4. Enhanced AI Evaluator

**Changes**:
- Receives MTF data in prompt
- Evaluates timeframe alignment
- Provides entry timing assessment
- Considers support/resistance from multiple timeframes

**Prompt Structure**:
```
Analyze this swing trading signal using multi-timeframe analysis (15m, 1h, 1d, 1w):

Symbol: RELIANCE
Direction: long
Entry: 2460
Stop Loss: 2401
Take Profit: 2500

Multi-Timeframe Analysis:
- MTF Score: 85/100
- Trend Alignment: ALIGNED (Bullish: 3, Bearish: 1)
- Momentum Alignment: ALIGNED (Bullish: 2, Bearish: 2)
- Support Levels: 2450, 2420, 2400
- Resistance Levels: 2500, 2520, 2550
- Timeframes Analyzed: m15, h1, d1, w1

Consider:
- Multi-timeframe trend alignment
- Support/resistance levels from weekly and daily charts
- Entry timing from 15m and 1h charts
- Overall structure across all timeframes
```

**Response Format**:
```json
{
  "score": 85,
  "confidence": 90,
  "summary": "Strong bullish trend across all timeframes...",
  "risk": "medium",
  "timeframe_alignment": "excellent",
  "entry_timing": "optimal"
}
```

---

### 5. Enhanced AI Ranker

**Changes**:
- Includes MTF data in ranking prompts
- Considers timeframe alignment in scoring
- Provides MTF-aware summaries

**Ranking Criteria**:
- Base screener score
- MTF score
- Trend alignment across timeframes
- Momentum alignment
- Entry recommendations quality

---

## Usage Examples

### Basic Multi-Timeframe Analysis

```ruby
# Analyze instrument with all timeframes
result = Swing::MultiTimeframeAnalyzer.call(
  instrument: instrument,
  include_intraday: true,
)

if result[:success]
  analysis = result[:analysis]
  puts "MTF Score: #{analysis[:multi_timeframe_score]}"
  puts "Trend Aligned: #{analysis[:trend_alignment][:aligned]}"
  puts "Support Levels: #{analysis[:support_resistance][:support_levels]}"
end
```

### Using in Screener

```ruby
# SwingScreener automatically uses MTF analysis
candidates = Screeners::SwingScreener.call(
  instruments: Instrument.where(segment: "equity"),
  limit: 20,
)

# Candidates include MTF data
candidates.each do |candidate|
  puts "#{candidate[:symbol]}: Score #{candidate[:score]}"
  puts "  MTF Score: #{candidate[:mtf_score]}"
  puts "  Trend Aligned: #{candidate[:multi_timeframe][:trend_alignment][:aligned]}"
end
```

### Using in Signal Generation

```ruby
# SignalBuilder automatically uses MTF analysis
signal = Strategies::Swing::SignalBuilder.call(
  instrument: instrument,
  daily_series: daily_series,
  weekly_series: weekly_series,
)

# Signal includes MTF metadata
puts "Entry: #{signal[:entry_price]}"
puts "Stop Loss: #{signal[:sl]}"
puts "Confidence: #{signal[:confidence]}"
puts "MTF Score: #{signal[:metadata][:multi_timeframe][:score]}"
```

### AI Evaluation with MTF

```ruby
# AI evaluator receives MTF data automatically
ai_result = Strategies::Swing::AIEvaluator.call(signal)

if ai_result[:success]
  puts "AI Score: #{ai_result[:ai_score]}"
  puts "Timeframe Alignment: #{ai_result[:timeframe_alignment]}"
  puts "Entry Timing: #{ai_result[:entry_timing]}"
end
```

---

## Configuration

### Enable/Disable Intraday Timeframes

```yaml
# config/algo.yml
swing_trading:
  multi_timeframe:
    include_intraday: true  # Set to false to use only daily/weekly
```

### MTF Weighting

The system uses default weights for combining timeframe scores:
- Weekly (1W): 30%
- Daily (1D): 40%
- Hourly (1H): 20%
- 15min (15M): 10%

These can be adjusted in `MultiTimeframeAnalyzer` if needed.

---

## Benefits

### 1. Better Entry Timing
- 15m and 1h charts provide precise entry points
- Reduces slippage and improves fill prices

### 2. Stronger Trend Confirmation
- Weekly and daily alignment ensures higher probability setups
- Reduces false signals from single-timeframe analysis

### 3. Better Stop Loss Placement
- Uses support/resistance from multiple timeframes
- More logical stop loss levels

### 4. Improved Take Profit Targets
- Uses resistance levels from weekly/daily charts
- More realistic profit targets

### 5. Enhanced AI Analysis
- AI receives comprehensive MTF context
- Better evaluation of trade quality
- More accurate risk assessment

---

## Performance Considerations

### Intraday Data Loading
- 15m and 1h candles are fetched on-demand (not stored)
- Cached for 5 minutes to reduce API calls
- Consider storing if frequently accessed

### Caching Strategy
- MTF analysis results can be cached per instrument
- Cache TTL: 15 minutes for intraday, 1 hour for daily/weekly
- AI evaluations cached for 24 hours

### Rate Limits
- OpenAI API: 50 calls/day default
- DhanHQ API: Respect rate limits for intraday fetches
- Consider batching MTF analysis for multiple instruments

---

## Future Enhancements

1. **Store Intraday Candles**: Persist 15m/1h candles to database for historical analysis
2. **MTF Backtesting**: Test MTF strategies on historical data
3. **Dynamic Timeframe Selection**: Automatically select best timeframes based on volatility
4. **MTF Risk Management**: Adjust position sizing based on MTF alignment
5. **MTF Exit Signals**: Use lower timeframes for exit timing

---

## Summary

The multi-timeframe swing trading system provides:

✅ **Comprehensive Analysis**: 15m, 1h, 1d, 1w timeframes  
✅ **Trend Alignment**: Confirms trend across all timeframes  
✅ **Support/Resistance**: Identifies key levels from multiple timeframes  
✅ **Entry Recommendations**: Suggests optimal entry zones  
✅ **AI Integration**: OpenAI evaluates MTF alignment and timing  
✅ **Better Signals**: Higher quality signals with improved confidence  

This creates a **professional-grade multi-timeframe trading system** that scales from retail to institutional-level analysis.
