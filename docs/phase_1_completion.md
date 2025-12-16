# Phase 1 Completion: Hard Contracts

## ✅ Task 1.1 — Trading Namespace Created
- Created `app/trading/` directory

## ✅ Task 1.2 — TradeFacts (READ-ONLY DATA)
- **File:** `app/trading/trade_facts.rb`
- **Rules:** Immutable, no risk logic, no quantities, no RR
- **Contains:**
  - `symbol`, `instrument_id`, `timeframe`
  - `indicators_snapshot` (hash)
  - `trend_flags`, `momentum_flags` (arrays)
  - `screener_score`
  - `setup_status`
  - `detected_at`
- **No entry, SL, TP here** ✅

## ✅ Task 1.3 — TradeIntent (WHAT WE WANT TO DO)
- **File:** `app/trading/trade_intent.rb`
- **Contains:**
  - `bias` (:long / :short / :avoid)
  - `proposed_entry`
  - `proposed_sl`
  - `proposed_targets` (Array of [price, probability])
  - `expected_rr`
  - `sizing_hint` (NOT quantity - just hint like "small", "medium", "large")
  - `strategy_key`
- **Still no execution, no orders** ✅

## ✅ Task 1.4 — TradeRecommendation (FINAL CONTRACT)
- **File:** `app/trading/trade_recommendation.rb`
- **Rules:**
  - Built ONLY from TradeFacts + TradeIntent ✅
  - Frozen/immutable ✅
  - Serializable (to_hash, to_json) ✅
- **Contains:**
  - All facts and intent (delegated)
  - `entry_price`, `stop_loss`, `target_prices` (from intent)
  - `risk_reward`, `risk_per_share`, `risk_amount`
  - `confidence_score` (from facts or override)
  - `quantity` (execution-level)
  - `invalidation_conditions`, `entry_conditions`
  - `reasoning` (array of strings)
- **Replaces loose trade_plan hash** ✅

## ✅ Feature Flag Created
- **File:** `config/trading.yml`
- **Flag:** `dto_enabled: false` (disabled by default)
- Includes placeholders for future phases

## Files Created
1. `app/trading/trade_facts.rb`
2. `app/trading/trade_intent.rb`
3. `app/trading/trade_recommendation.rb`
4. `config/trading.yml`

## Next Steps (Phase 2)
- Create adapters to convert existing ScreenerResult → TradeFacts
- Create adapters to convert trade_plan hash → TradeIntent
- Wire adapters behind feature flag

## Notes
- All classes are immutable (frozen where appropriate)
- No database writes
- No external dependencies
- Pure Ruby objects
- Ready for Phase 2 adapters
