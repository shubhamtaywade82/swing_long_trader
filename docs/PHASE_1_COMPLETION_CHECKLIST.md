# Phase 1 Completion Checklist - Making the System Measurable

## ✅ Step 1: Outcome Tracking

### TradeOutcome Model
- [x] Model exists with all required fields
- [x] Validations in place
- [x] Scopes for filtering (open, closed, winners, losers)
- [x] Metrics calculation (R-multiple, P&L, holding days)
- [x] Class methods for analysis (win_rate, expectancy)

### Exit Reasons
- [x] `sl_hit` (stop loss hit)
- [x] `tp_hit` (take profit hit) 
- [x] `time_based` (max holding days)
- [x] `manual` (manual exit)
- [x] `signal_invalidated` (signal no longer valid)

**Status:** ✅ Complete

---

## ✅ Step 2: Wire Outcome Tracking to Paper Trading

### Creation Flow
- [x] `TradeOutcomes::Creator` service exists
- [x] `SwingScreenerJob.create_trade_outcomes_for_final_candidates` creates outcomes for Tier 1
- [ ] `PaperTrading::Executor.create_trade_outcome_if_from_screener` - **NEEDS IMPLEMENTATION**

### Update Flow
- [x] `TradeOutcomes::Updater` service exists
- [x] `PaperTrading::Simulator.update_trade_outcome_for_paper_position` updates on exit
- [x] `SwingPosition.update_trade_outcome_on_close` updates on exit

### Exit Logic
- [x] SL hit detection
- [x] TP hit detection
- [x] Time-based exit (max holding days)
- [ ] Manual exit (needs UI/API endpoint)
- [ ] Signal invalidation (needs logic)

**Status:** ⚠️ Mostly Complete - Missing executor link

---

## ✅ Step 3: ScreenerRun Metrics

### Required Metrics
- [x] `eligible_count` - Layer 1 results
- [x] `ranked_count` - Layer 2 results
- [x] `ai_evaluated_count` - Layer 3 results
- [x] `final_count` - Layer 4 results
- [x] `ai_calls_count` - AI API calls
- [x] `ai_cost` - Estimated AI cost
- [x] `overlap_with_prev_run` - % overlap with previous run
- [x] Compression metrics (efficiency, ratio)
- [x] Quality metrics (avg scores)
- [x] Tier distribution

### Health Monitoring
- [x] `health_status` method checks for issues
- [x] Compression efficiency validation
- [x] Eligible/final count validation
- [x] Overlap validation
- [x] AI cost validation

**Status:** ✅ Complete

---

## 🔧 What Needs to Be Fixed

### 1. Link Paper Trading Executor to TradeOutcome

**File:** `app/services/paper_trading/executor.rb`

**Issue:** `create_trade_outcome_if_from_screener` method is called but not implemented.

**Fix:** Implement method to:
- Check if signal came from a screener run
- Find or create TradeOutcome
- Link to position

### 2. Complete Exit Reason Mapping

**File:** `app/services/paper_trading/simulator.rb`

**Issue:** Exit reasons need to match exact spec:
- `sl_hit` ✅
- `tp_hit` ✅  
- `time_based` ✅
- `manual` - needs implementation
- `signal_invalidated` - needs implementation

### 3. Add ScreenerResult Scopes

**File:** `app/models/screener_result.rb`

**Issue:** MetricsCalculator uses scopes that may not exist:
- `by_stage("screener")`
- `by_stage("ranked")`
- `ai_evaluated`

**Fix:** Add these scopes to ScreenerResult model.

---

## 📊 Verification Steps

### 1. Test TradeOutcome Creation

```ruby
# In Rails console
run = ScreenerRun.last
candidate = run.screener_results.by_stage("final").first

# Should create TradeOutcome
outcome = TradeOutcomes::Creator.call(
  screener_run: run,
  candidate: candidate.to_candidate_hash,
  trading_mode: "paper"
)

# Verify outcome created
TradeOutcome.find_by(screener_run_id: run.id, symbol: candidate.symbol)
```

### 2. Test Paper Trading Execution

```ruby
# Create a signal from screener
signal = {
  instrument_id: 1,
  symbol: "RELIANCE",
  direction: :long,
  entry_price: 2500,
  qty: 1,
  sl: 2400,
  tp: 2700
}

# Execute paper trade
result = PaperTrading::Executor.execute(signal)

# Verify TradeOutcome created
position = result[:position]
TradeOutcome.find_by(position_id: position.id, position_type: "paper_position")
```

### 3. Test Exit Tracking

```ruby
# Get open position
position = PaperPosition.open.first

# Simulate exit
PaperTrading::Simulator.check_exits(portfolio: position.paper_portfolio)

# Verify TradeOutcome updated
outcome = TradeOutcome.find_by(position_id: position.id)
outcome.closed? # Should be true
outcome.exit_reason # Should be set
outcome.r_multiple # Should be calculated
```

### 4. Test ScreenerRun Metrics

```ruby
# Get latest run
run = ScreenerRun.last

# Calculate metrics
ScreenerRuns::MetricsCalculator.call(run)

# Verify metrics
run.metrics_hash
# Should include: eligible_count, ranked_count, ai_evaluated_count, final_count, etc.

# Check health
run.health_status
```

---

## 🎯 Next Actions

1. **Implement `create_trade_outcome_if_from_screener`** in PaperTrading::Executor
2. **Add missing scopes** to ScreenerResult model
3. **Add manual exit** functionality
4. **Add signal invalidation** logic
5. **Test end-to-end flow** from screener → paper trade → exit → outcome

---

## ✅ Completion Criteria

- [ ] TradeOutcome created when paper trade executes from screener
- [ ] TradeOutcome updated when position exits (all exit reasons)
- [ ] All ScreenerRun metrics calculated and persisted
- [ ] Health status checks working
- [ ] End-to-end test passes (screener → trade → exit → outcome)
