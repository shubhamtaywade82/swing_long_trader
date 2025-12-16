# Screener Service Contract

## 🎯 Purpose

This document defines the **strict contract** for Screener services in `swing_long_trader`. This contract prevents the system from becoming a confusing "indicator dashboard" and maintains clear separation of concerns.

---

## 1️⃣ What a Screener IS vs IS NOT

### ❌ What a Screener is NOT

- ❌ Not a list of bullish stocks
- ❌ Not an indicator dump (RSI, ADX, MACD columns)
- ❌ Not a trading signal generator
- ❌ Not a "Buy / Sell" engine
- ❌ Not capital-aware
- ❌ Not AI-aware (directly)
- ❌ Not setup-aware (READY vs WAIT)
- ❌ Not trade-plan-aware (SL/TP/Quantity)

If your screener tries to do these → it becomes bloated and misleading.

---

### ✅ What a Screener IS

In **swing_long_trader**, a screener is:

> **A deterministic market filter that identifies CANDIDATES worth further evaluation**

That's it.

Think of it as:

> "Which stocks deserve attention today based on objective rules?"

Everything else happens **after** the screener.

---

## 2️⃣ Screener Service Responsibilities (Non-negotiable)

### 🎯 Screener Service = `Candidate Generator`

**Input:**
- Instrument universe (500 stocks)
- Timeframes (swing or long-term)
- Indicator configuration
- ScreenerRun context

**Output:**
- `ScreenerResult` records (candidates only)
- No trade plan
- No quantity
- No SL/TP
- No AI opinion
- No setup status
- No recommendation

---

### ✅ What the Screener MUST do

#### 1. **Trend Eligibility Check**

Answer only:

> "Is this stock directionally aligned for this strategy?"

Examples:
- Swing: Daily + 1H bullish
- Long-term: Weekly + Daily bullish

Binary decision:

```ruby
eligible: true / false
```

---

#### 2. **Base Technical Scoring**

This is *ranking*, not decision-making.

- EMA alignment
- Supertrend direction
- ADX strength
- RSI sanity (not overbought extreme)

Outputs:

```ruby
base_score (0–100)
mtf_score (0–100)
combined_score (0–100)
```

This helps **sort**, not **trade**.

---

#### 3. **Context Snapshot (Facts, not opinions)**

The screener should capture **raw facts** that later services need:

Examples:
- `distance_from_ema20`
- `atr_percent`
- `trend_age`
- `last_bos_days_ago`
- `range_high` / `range_low`
- `recent_runup_percent`

These are **inputs**, not conclusions.

---

#### 4. **Persist Results**

Each screener run must persist:

```ruby
screener_run_id
instrument_id
timeframe
trend_state
scores
raw_context_metrics
```

No rendering logic here.

---

### 🚫 What the Screener MUST NOT do

❌ Decide entry timing
❌ Decide SL / TP
❌ Apply capital rules
❌ Call AI
❌ Send Telegram alerts
❌ Label "BUY / SELL"
❌ Determine setup status (READY vs WAIT)
❌ Generate trade plans
❌ Create recommendations

If it does → that logic belongs elsewhere.

---

## 3️⃣ ScreenerResult Data Contract

### ✅ Fields ALLOWED at Screener Stage

```ruby
# Core identification
instrument_id: Integer
symbol: String
screener_type: String ("swing" | "longterm")
screener_run_id: Integer
stage: String ("screener")  # Must be "screener" at this stage

# Scoring (ranking only)
score: Decimal (0-100)
base_score: Decimal (0-100)
mtf_score: Decimal (0-100)

# Raw indicators (facts)
indicators: JSON {
  ema20: Decimal,
  ema50: Decimal,
  rsi: Decimal,
  adx: Decimal,
  atr: Decimal,
  supertrend: Hash,
  volume: Hash,
  # ... other technical indicators
}

# Context metrics (facts)
metadata: JSON {
  ltp: Decimal,
  candles_count: Integer,
  latest_timestamp: DateTime,
  trend_alignment: Array,
  volatility: Hash {
    atr: Decimal,
    atr_percent: Decimal,
    level: String
  },
  momentum: Hash {
    change_5d: Decimal,
    rsi: Decimal,
    level: String
  },
  # Raw context facts (no opinions)
  distance_from_ema20: Decimal,
  distance_from_ema50: Decimal,
  trend_age: Integer,
  # ... other context metrics
}

# Multi-timeframe analysis (facts)
multi_timeframe: JSON {
  score: Decimal,
  trend_alignment: Hash,
  momentum_alignment: Hash,
  timeframes_analyzed: Array,
  # ... other MTF facts
}

# Timestamps
analyzed_at: DateTime
created_at: DateTime
updated_at: DateTime
```

---

### ❌ Fields FORBIDDEN at Screener Stage

These fields must be `nil` or not set at screener stage:

```ruby
# Setup classification (belongs to SetupClassifier)
setup_status: nil  # Must be nil
setup_reason: nil
invalidate_if: nil
entry_conditions: nil

# Trade planning (belongs to TradePlanner)
trade_plan: nil
accumulation_plan: nil
recommendation: nil

# AI evaluation (belongs to AIEvaluator)
ai_confidence: nil
ai_risk: nil
ai_holding_days: nil
ai_comment: nil
ai_avoid: nil
ai_status: nil
ai_eval_id: nil

# Trade quality (belongs to TradeQualityRanker)
trade_quality_score: nil
trade_quality_breakdown: nil
```

---

## 4️⃣ Post-Screener Pipeline

The correct flow (you already have this, just clarifying):

```
Screener (Candidate Generator)
   ↓
TradeQualityRanker (Quality Filter)
   ↓
SetupClassifier (READY vs WAIT)
   ↓
AIEvaluator (AI Opinion)
   ↓
FinalSelector (Portfolio Constraints)
   ↓
TradePlanner (SL/TP/Quantity)
   ↓
UI / Telegram (Actionable Recommendations)
```

Each stage answers **one question only**.

---

## 5️⃣ Validation Rules

### Model Validation

Add to `ScreenerResult` model:

```ruby
validate :screener_stage_contract, if: -> { stage == "screener" }

def screener_stage_contract
  errors.add(:setup_status, "must be nil at screener stage") if setup_status.present?
  errors.add(:trade_plan, "must be nil at screener stage") if metadata_hash.dig("trade_plan").present?
  errors.add(:recommendation, "must be nil at screener stage") if metadata_hash.dig("recommendation").present?
  # ... other validations
end
```

### Service Validation

Add to screener services:

```ruby
def persist_result(analysis)
  # Ensure no forbidden fields
  analysis.delete(:setup_status)
  analysis.delete(:trade_plan)
  analysis.delete(:recommendation)

  # Only persist allowed fields
  ScreenerResult.upsert_result(...)
end
```

---

## 6️⃣ UI Rendering Contract

### Screener Tab = **Market State View**

Label it clearly:

> "Market Scan – Candidates Only"

#### Columns that SHOULD be shown

- Symbol
- Trend State (Bullish / Bearish)
- Combined Score
- Trend Age
- Distance from EMA
- Volatility (ATR%)
- RSI
- ADX

#### Columns that SHOULD NOT be shown

- Buy / Sell
- Entry
- SL
- TP
- Quantity
- Setup Status
- Recommendation

This prevents false confidence.

---

### Recommendations Tab = **Actionable View**

> "Ready to Trade"

#### Columns that SHOULD be shown

- Symbol
- Setup Status
- Entry Zone
- SL
- TP
- Quantity
- Risk Amount
- AI Confidence
- Recommendation

---

## 7️⃣ Enforcement

### Hard Rule

> A Screener service may ONLY create or update `ScreenerResult` records with `stage: "screener"`
> It must NEVER create:
>
> - TradePlan
> - Alert
> - Order
> - Telegram message
> - Setup status
> - Recommendation

This one rule will keep your system clean for years.

---

## 8️⃣ Migration Path

1. **Phase 1**: Remove SetupDetector and TradePlanBuilder calls from screener services
2. **Phase 2**: Add validation to ScreenerResult model
3. **Phase 3**: Update UI to show different columns per tab
4. **Phase 4**: Move SetupDetector to SetupClassifier service (called by TradeQualityRanker)
5. **Phase 5**: Document TradePlanner responsibilities

---

## 9️⃣ How to Judge if Your Screener Is Correct

Ask only ONE question:

> "If I remove AI, capital, and trade execution, does the screener still make sense?"

If yes → correct
If no → it's overloaded

---

## ✅ Summary

- **Screener = Candidate Generator**
- **Rendering = Informational, not actionable**
- **Decision-making = Later stages**
- **Trading instructions = FinalSelector + TradePlanner**

You're already 70% there.
This clarity will prevent the last 30% from becoming a mess.
