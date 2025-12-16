# Phase 0: System Mapping (READ ONLY)

## Where Screener Outputs Are Built

**Location:** `app/services/screeners/swing_screener.rb` and `app/services/screeners/longterm_screener.rb`

**Process:**
1. `SwingScreener#analyze_instrument` builds candidate hash with:
   - `instrument_id`, `symbol`, `score` (combined_score)
   - `indicators` (EMA, RSI, MACD, ADX, Supertrend, ATR)
   - `multi_timeframe` analysis
   - `metadata` (trend_alignment, volatility, momentum)

2. `Screeners::SetupDetector.call` determines `setup_status`:
   - `READY` - Ready to trade
   - `WAIT_PULLBACK` - Wait for pullback
   - `WAIT_BREAKOUT` - Wait for breakout
   - `NOT_READY` - Not ready
   - `IN_POSITION` - Already in position

3. For `READY` setups, `Screeners::TradePlanBuilder.call` generates `trade_plan`:
   - `entry_price`, `stop_loss`, `take_profit`
   - `risk_reward`, `risk_per_share`, `risk_amount`
   - `quantity`, `capital_used`, `entry_zone`

4. Candidate hash persisted to `ScreenerResult` model via `persist_result`

**Output Format:** Hash with nested `trade_plan` hash (not a formal DTO)

---

## Where Trade Plans Are Generated

**Location:** `app/services/screeners/trade_plan_builder.rb`

**Process:**
1. Only generates for `READY` setups (validated by `SetupDetector`)
2. Calculates entry using EMA20 proximity or current LTP
3. Calculates stop loss using swing low, EMA50, or 2 ATR
4. Calculates take profit using 2.5R multiple or structure target
5. Rejects if `risk_reward < 2.5`
6. Calculates quantity based on portfolio capital and risk limits

**Output:** Hash with keys: `entry_price`, `stop_loss`, `take_profit`, `risk_reward`, `quantity`, etc.

**Note:** Long-term uses `LongtermTradePlanBuilder` with `accumulation_plan` format (different structure)

---

## Where AI Is Currently Invoked

**Location:** `app/services/screeners/ai_ranker.rb` (class `Screeners::AIEvaluator`)

**Process:**
1. Called after screener completes (in `Screeners::FinalSelector` or `AIRankerJob`)
2. Calls `AI::UnifiedService.call` with candidate data
3. Parses JSON response: `{confidence, risk, holding_days, avoid, comment}`
4. Filters candidates: drops if `avoid == true` or `confidence < 6.5`
5. Persists AI results to `ScreenerResult` (ai_confidence, ai_risk, ai_avoid, etc.)

**Problem:** AI directly filters candidates - no deterministic fallback if AI fails

**Integration Points:**
- `Screeners::FinalSelector` calls `AIEvaluator` before final selection
- `Screeners::AIEvaluator` uses `AI::UnifiedService` which auto-detects Ollama/OpenAI

---

## Where Orders Are Executed

**Location:** `app/services/strategies/swing/executor.rb` (class `Strategies::Swing::Executor`)

**Process:**
1. Validates signal (entry_price, qty, direction present)
2. Checks risk limits (balance, position size, total exposure)
3. Checks circuit breaker (failure rate < 50%)
4. Checks manual approval (first 30 trades require approval)
5. Places order via:
   - `Dhan::Orders.place_order` (live trading)
   - `PaperTrading::Executor.execute` (paper trading)

**Order Creation:**
- Creates `Order` record with `requires_approval` flag if needed
- Creates `TradingSignal` record for tracking
- Creates `Position` record after execution

**Approval Flow:**
- `Orders::Approval.approve` → `Orders::ProcessApprovedJob` → `Dhan::Orders.place_order`

---

## Key Models

- `ScreenerResult` - Stores screener output (score, indicators, trade_plan in metadata JSON)
- `ScreenerRun` - Tracks screener execution
- `TradingSignal` - Generated signals (entry_price, qty, direction)
- `Order` - Order records (pending/approved/rejected/executed)
- `Position` - Open positions (live trading)
- `PaperTrading::Position` - Paper trading positions

---

## Data Flow Summary

```
Screener → Candidate Hash → SetupDetector → TradePlanBuilder → ScreenerResult
                                                                    ↓
                                                              AIEvaluator (optional)
                                                                    ↓
                                                              FinalSelector
                                                                    ↓
                                                              TradingSignal
                                                                    ↓
                                                              Swing::Executor
                                                                    ↓
                                                              Order (pending/approved)
                                                                    ↓
                                                              Dhan::Orders / PaperTrading
```

---

**No refactors performed - mapping only**
