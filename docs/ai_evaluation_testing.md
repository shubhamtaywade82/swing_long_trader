# AI Evaluation Testing Guide

## Overview

AI evaluation is fully tested across all testing methods. This guide shows how to test the AI evaluator with multi-timeframe data.

---

## Testing Methods

### 1. Rake Task (Recommended)

**Command:**
```bash
rake test:mtf:ai_eval[RELIANCE]
rake test:mtf:ai_eval[TCS]
rake test:mtf:ai_eval[INFY]
```

**What it does:**
1. ✅ Generates signal using SignalBuilder (with MTF data)
2. ✅ Calls AI Evaluator with the signal
3. ✅ Displays AI score, confidence, timeframe alignment, entry timing
4. ✅ Shows AI summary and risk assessment

**Example Output:**
```
🤖 Testing AI Evaluator with MTF for RELIANCE
================================================================================
📊 Signal Generated:
   Entry: ₹2460, SL: ₹2401, TP: ₹2500
   Confidence: 85/100

🤖 Calling AI Evaluator...

✅ AI Evaluation successful!

📊 AI Results:
   AI Score: 88/100
   AI Confidence: 90/100
   Timeframe Alignment: EXCELLENT
   Entry Timing: OPTIMAL
   Risk: MEDIUM

📝 Summary:
   Strong bullish trend across all timeframes (15m, 1h, 1d, 1w) with excellent 
   alignment. Entry timing is optimal with price near support level. Risk-reward 
   ratio is favorable.

💾 Cached: No
```

---

### 2. Rails Console

**Load helpers:**
```ruby
load 'lib/console_helpers.rb'
```

**Test AI evaluation:**
```ruby
# Simple test
ai_eval("RELIANCE")

# Or step by step
signal = mtf_signal("RELIANCE")
ai_result = Strategies::Swing::AIEvaluator.call(signal)
```

**Example:**
```ruby
rails console
> load 'lib/console_helpers.rb'
✅ Console helpers loaded!

> ai_eval("RELIANCE")

📈 Signal: RELIANCE
============================================================
Entry: ₹2460
SL: ₹2401
TP: ₹2500
RR: 2.5:1
Qty: 75
Confidence: 85/100

🤖 AI Evaluation...
AI Score: 88/100
Timeframe Alignment: excellent
Entry Timing: optimal
Summary: Strong bullish trend across all timeframes...
```

---

### 3. Rails Runner

**Command:**
```bash
rails runner script/test_console.rb ai_eval RELIANCE
rails runner script/test_console.rb ai_eval TCS
```

**What it does:**
- Generates signal
- Calls AI evaluator
- Displays results

---

### 4. Complete Flow Test

**Command:**
```bash
rake test:mtf:full_flow[RELIANCE]
```

**What it tests:**
1. ✅ Multi-Timeframe Analysis
2. ✅ Signal Generation
3. ✅ **AI Evaluation** ← Included here!

**Example Output:**
```
🔄 Testing Complete Flow for RELIANCE
================================================================================

1️⃣ Multi-Timeframe Analysis...
   ✅ MTF Score: 85/100
   ✅ Trend Aligned: YES

2️⃣ Signal Generation...
   ✅ Entry: ₹2460, SL: ₹2401, TP: ₹2500
   ✅ Confidence: 85/100

3️⃣ AI Evaluation...
   ✅ AI Score: 88/100
   ✅ Timeframe Alignment: EXCELLENT
   ✅ Entry Timing: OPTIMAL

📊 Summary:
   Symbol: RELIANCE
   Direction: LONG
   Entry: ₹2460
   Stop Loss: ₹2401
   Take Profit: ₹2500
   Risk-Reward: 2.5:1
   Quantity: 75
   Confidence: 85/100
   AI Score: 88/100
   AI Timeframe Alignment: EXCELLENT
```

---

## What Gets Tested

### ✅ Signal Generation with MTF
- Signal includes multi-timeframe metadata
- Entry/exit prices use MTF support/resistance
- Confidence enhanced with MTF alignment

### ✅ AI Prompt with MTF Data
The AI evaluator receives:
- Signal details (entry, SL, TP, RR)
- Multi-timeframe score
- Trend alignment across timeframes
- Momentum alignment
- Support/resistance levels
- Timeframes analyzed (15m, 1h, 1d, 1w)

### ✅ AI Response Parsing
- Parses JSON response
- Extracts score, confidence, summary, risk
- Extracts timeframe alignment and entry timing
- Handles errors gracefully

### ✅ Caching
- Results are cached for 24 hours
- Reduces API calls
- Shows cache status in output

---

## AI Evaluation Output Fields

| Field | Description | Example |
|-------|-------------|---------|
| `ai_score` | Overall quality score (0-100) | 88 |
| `ai_confidence` | Confidence in analysis (0-100) | 90 |
| `timeframe_alignment` | MTF alignment quality | "excellent" |
| `entry_timing` | Entry timing assessment | "optimal" |
| `ai_risk` | Risk level | "medium" |
| `ai_summary` | Brief analysis summary | "Strong bullish..." |
| `cached` | Whether result was cached | true/false |

---

## Testing Multiple Symbols

### Batch Testing

**Rake Task:**
```bash
# Test multiple symbols
for symbol in RELIANCE TCS INFY HDFCBANK; do
  echo "Testing $symbol..."
  rake test:mtf:ai_eval[$symbol]
  echo ""
done
```

**Rails Console:**
```ruby
symbols = ["RELIANCE", "TCS", "INFY", "HDFCBANK"]
symbols.each do |symbol|
  puts "\n=== Testing #{symbol} ==="
  ai_eval(symbol)
end
```

---

## Troubleshooting

### Issue: OpenAI API Error

**Symptoms:**
```
❌ AI Evaluation failed: No API key configured
```

**Solution:**
```bash
# Set API key
export OPENAI_API_KEY="your-api-key-here"

# Or in Rails console
ENV["OPENAI_API_KEY"] = "your-api-key-here"
```

### Issue: Rate Limit Exceeded

**Symptoms:**
```
❌ AI Evaluation failed: Rate limit exceeded
```

**Solution:**
- Default limit: 50 calls/day
- Wait for next day or increase limit in config
- Use cached results when available

### Issue: JSON Parse Error

**Symptoms:**
```
❌ Failed to parse response
```

**Solution:**
- Check OpenAI API response format
- Verify model is returning valid JSON
- Check logs for actual response

---

## Advanced Testing

### Test with Custom Signal

```ruby
# Create custom signal
signal = {
  instrument_id: instrument.id,
  symbol: "RELIANCE",
  direction: :long,
  entry_price: 2460.0,
  sl: 2401.0,
  tp: 2500.0,
  rr: 2.5,
  confidence: 85.0,
  holding_days_estimate: 12,
  metadata: {
    multi_timeframe: {
      score: 85,
      trend_alignment: { aligned: true, bullish_count: 3 },
      momentum_alignment: { aligned: true },
      timeframes_analyzed: ["m15", "h1", "d1", "w1"],
    }
  }
}

# Evaluate with AI
result = Strategies::Swing::AIEvaluator.call(signal)
```

### Test AI Ranker (Multiple Evaluations)

```bash
rake test:mtf:ai_rank[5]
```

This tests:
- ✅ Ranking multiple candidates with AI
- ✅ Each candidate gets AI evaluation
- ✅ Results sorted by combined score

---

## Summary

✅ **AI Evaluation IS fully tested** in:
- ✅ Rake task: `rake test:mtf:ai_eval[SYMBOL]`
- ✅ Console helper: `ai_eval(symbol)`
- ✅ Rails runner: `rails runner script/test_console.rb ai_eval SYMBOL`
- ✅ Complete flow: `rake test:mtf:full_flow[SYMBOL]` (includes AI eval)
- ✅ AI ranker: `rake test:mtf:ai_rank[LIMIT]` (tests multiple AI evals)

All testing methods include AI evaluation! 🚀
