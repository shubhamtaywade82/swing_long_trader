# Phase 3 Completion: Decision Engine (Deterministic)

## ✅ Task 3.1 — Decision Engine Skeleton
- **Folders:** `app/trading/decision_engine/`
- **Files Created:**
  - `engine.rb` - Main orchestrator
  - `validator.rb` - Structure validation
  - `risk_rules.rb` - Risk management
  - `setup_quality.rb` - Setup filtering
  - `portfolio_constraints.rb` - Portfolio checks
- **Rules:**
  - ✅ No database writes
  - ✅ No LLM calls
  - ✅ No WebSocket dependency
  - ✅ Pure functions only

## ✅ Task 3.2 — Validator
- **File:** `app/trading/decision_engine/validator.rb`
- **Checks:**
  - Required fields present (entry_price, stop_loss, quantity, symbol, instrument_id)
  - Numeric sanity (positive values, entry > SL for long, entry < SL for short)
  - RR ≥ configured minimum (default 2.0)
  - Confidence ≥ configured minimum (default 60.0)
  - Bias allowed (:long or :short)
  - Avoid flag not set
  - Target prices exist
- **Returns:** `{ approved: true/false, reason:, errors: [] }`

## ✅ Task 3.3 — Risk Rules
- **File:** `app/trading/decision_engine/risk_rules.rb`
- **Checks:**
  - Per-trade risk % (must not exceed daily limit)
  - Daily risk % (sum of today's positions + new trade)
  - Volatility cap (ATR % of price, default max 8%)
  - Uses existing Portfolio models if available (CapitalAllocationPortfolio)
  - Falls back gracefully if no portfolio
- **Returns:** `{ approved: true/false, reason:, errors: [] }`

## ✅ Task 3.4 — Setup Quality Filter
- **File:** `app/trading/decision_engine/setup_quality.rb`
- **Checks:**
  - Trend still valid (bullish for long, bearish for short)
  - Momentum not diverging (no conflicting signals)
  - No immediate invalidation (setup_status != NOT_READY)
- **Rules:**
  - ✅ NO indicators recalculated
  - ✅ Reuses existing values from TradeFacts
- **Returns:** `{ approved: true/false, reason:, errors: [] }`

## ✅ Task 3.5 — Portfolio Constraints
- **File:** `app/trading/decision_engine/portfolio_constraints.rb`
- **Checks:**
  - Max positions per symbol (default 1)
  - Capital availability (required vs available)
- **Rules:**
  - ✅ Uses existing Portfolio models if available
  - ✅ Passes if no portfolio provided
- **Returns:** `{ approved: true/false, reason:, errors: [] }`

## ✅ Task 3.6 — Engine Orchestrator
- **File:** `app/trading/decision_engine/engine.rb`
- **Process:**
  1. Checks feature flag (disabled by default)
  2. Runs Validator
  3. Runs RiskRules
  4. Runs SetupQuality
  5. Runs PortfolioConstraints
  6. Returns decision with full path
- **Returns:** `{ approved: true/false, recommendation:, decision_path: [], checked_at: }`

## Configuration
- **File:** `config/trading.yml`
- **Flag:** `decision_engine.enabled: false` (disabled by default)
- **Config Values:**
  - `min_risk_reward: 2.0`
  - `min_confidence: 60.0`
  - `max_volatility_pct: 8.0`
  - `max_positions_per_symbol: 1`
  - `max_daily_risk_pct: 2.0`

## Files Created
1. `app/trading/decision_engine/engine.rb`
2. `app/trading/decision_engine/validator.rb`
3. `app/trading/decision_engine/risk_rules.rb`
4. `app/trading/decision_engine/setup_quality.rb`
5. `app/trading/decision_engine/portfolio_constraints.rb`

## Files Modified
1. `app/trading/config.rb` (exposed config_value for Engine use)

## Testing Checklist
- [ ] Validator rejects invalid structures
- [ ] Validator accepts valid structures
- [ ] RiskRules enforces daily risk limits
- [ ] RiskRules checks volatility caps
- [ ] SetupQuality filters weak setups
- [ ] PortfolioConstraints checks position limits
- [ ] Engine orchestrates all checks correctly
- [ ] Engine returns disabled response when flag is off
- [ ] All components are pure functions (no side effects)

## Behavior Verification
- ✅ NO database writes
- ✅ NO LLM calls
- ✅ NO WebSocket dependency
- ✅ Pure functions only
- ✅ Feature flag controls execution
- ✅ Works with or without portfolio
- ✅ Reuses existing indicator values (no recalculation)

## Integration Example
```ruby
# Behind feature flag
if Trading::Config.dto_enabled? && Trading::Config.decision_engine_enabled?
  recommendation = screener_result.to_trade_recommendation(portfolio: portfolio)
  decision = Trading::DecisionEngine::Engine.call(
    trade_recommendation: recommendation,
    portfolio: portfolio,
  )
  
  if decision[:approved]
    # Proceed with trade
  else
    # Rejected: decision[:reason], decision[:errors]
  end
end
```

## Next Steps (Phase 4)
- Create SystemContext object
- Add market regime, recent PnL, drawdown tracking
- Inject SystemContext into Decision Engine
- Test with historical data
