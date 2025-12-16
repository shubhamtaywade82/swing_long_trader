# Screener Contract Implementation Summary

## ✅ Completed

### 1. Contract Documentation
- Created `docs/SCREENER_CONTRACT.md` with full specification
- Defined what screener IS vs IS NOT
- Documented allowed vs forbidden fields
- Established validation rules

### 2. Screener Service Refactoring
- **SwingScreener**: Removed `SetupDetector` and `TradePlanBuilder` calls
- **LongtermScreener**: Removed `LongtermSetupDetector` and `LongtermTradePlanBuilder` calls
- Both services now only generate candidates (trend eligibility, scoring, context metrics)
- Removed recommendation building methods

### 3. Data Persistence Cleanup
- Both screener services now clean metadata before persistence
- Removed forbidden fields: `setup_status`, `trade_plan`, `accumulation_plan`, `recommendation`
- Only candidate generation data is persisted at screener stage

### 4. Model Validation
- Added `screener_stage_contract` validation to `ScreenerResult` model
- Enforces that screener stage cannot contain:
  - Setup classification fields
  - Trade planning fields
  - Recommendations
  - AI evaluation fields
  - Trade quality fields

---

## 🔄 Next Steps

### 1. SetupClassifier Service ✅ COMPLETED

**Implementation:**
- Created `app/services/screeners/setup_classifier.rb` as dedicated service
- Wraps `SetupDetector` and calls it after `TradeQualityRanker`, before `AIEvaluator`
- Persists `setup_status`, `setup_reason`, `invalidate_if`, `entry_conditions` to metadata
- Updates `ScreenerResult` stage to `"ranked"` (or keeps existing stage)

**Pipeline Flow:**
```
Screener (candidates) - stage: "screener"
  ↓
TradeQualityRanker (quality filter) - stage: "ranked"
  ↓
SetupClassifier (READY vs WAIT) - stage: "ranked" (with setup_status in metadata) ✅
  ↓
AIEvaluator (AI opinion) - stage: "ai_evaluated"
```

**Files Updated:**
- ✅ `app/services/screeners/setup_classifier.rb` - NEW service
- ✅ `app/jobs/screeners/swing_screener_job.rb` - Added Layer 2.5
- ⏳ `app/jobs/screeners/longterm_screener_job.rb` - TODO: Add similar pipeline if needed

---

### 2. UI Column Redesign (Medium Priority)

**Current Problem:**
- Screener tab shows actionable columns (Entry, SL, TP, Setup Status)
- This creates confusion - users think they can trade directly

**Action Required:**

#### Screener Tab (Candidates Only)
**SHOW:**
- Symbol
- Trend State (Bullish/Bearish)
- Combined Score
- Base Score
- MTF Score
- Trend Age
- Distance from EMA20
- Distance from EMA50
- Volatility (ATR%)
- RSI
- ADX

**HIDE:**
- Setup Status
- Entry Zone
- SL
- TP
- Quantity
- Recommendation
- AI Confidence

#### Recommendations Tab (Actionable)
**SHOW:**
- Symbol
- Setup Status
- Entry Zone
- SL
- TP
- Quantity
- Risk Amount
- AI Confidence
- Recommendation

**Files to Update:**
- `app/views/screeners/swing.html.erb`
- `app/views/screeners/longterm.html.erb`
- `app/views/screeners/_screener_table.html.erb`
- `app/views/screeners/_screener_table_compact.html.erb`

---

### 3. TradePlanner Service Documentation (Low Priority)

**Current State:**
- `TradePlanBuilder` exists for swing
- `LongtermTradePlanBuilder` exists for long-term
- Both are called from screener services (WRONG - already fixed)

**Action Required:**
- Document that TradePlanner is responsible for:
  - SL/TP calculation
  - Quantity calculation (portfolio-aware)
  - Risk amount calculation
  - Risk-reward ratio validation
  - Entry zone definition

**Files to Document:**
- `app/services/screeners/trade_plan_builder.rb`
- `app/services/screeners/longterm_trade_plan_builder.rb`
- Create `docs/TRADE_PLANNER_CONTRACT.md`

---

## 🎯 Migration Notes

### Breaking Changes
1. **Screener results at `screener` stage no longer have:**
   - `setup_status`
   - `trade_plan` / `accumulation_plan`
   - `recommendation`

2. **UI may break if it expects these fields:**
   - Check all views that display screener results
   - Update to handle nil values gracefully
   - Show "Not yet classified" for setup status

### Backward Compatibility
- Existing `ScreenerResult` records with old data will still work
- Validation only applies to new records or updates
- Old records can be migrated later if needed

### Testing Required
1. Run screener and verify no forbidden fields in metadata
2. Verify validation errors if forbidden fields are added
3. Test UI with nil setup_status/trade_plan
4. Verify pipeline still works after removing setup detection from screener

---

## 📋 Checklist

- [x] Create contract documentation
- [x] Remove SetupDetector from screener services
- [x] Remove TradePlanBuilder from screener services
- [x] Clean metadata before persistence
- [x] Add model validation
- [ ] Move SetupDetector to correct layer
- [ ] Update UI columns for Screener tab
- [ ] Update UI columns for Recommendations tab
- [ ] Document TradePlanner responsibilities
- [ ] Test full pipeline
- [ ] Update job pipelines

---

## 🔍 How to Verify Contract Compliance

### Check Screener Service
```ruby
# In Rails console
result = ScreenerResult.where(stage: "screener").last
result.metadata_hash.keys
# Should NOT contain: setup_status, trade_plan, accumulation_plan, recommendation
```

### Check Validation
```ruby
# Try to save with forbidden field
result = ScreenerResult.new(
  stage: "screener",
  metadata: { setup_status: "READY" }.to_json
)
result.valid?
# Should be false with error about setup_status
```

### Check Service Output
```ruby
# Run screener
candidates = Screeners::SwingScreener.call(limit: 10)
candidates.first.keys
# Should NOT contain: setup_status, trade_plan, recommendation
```

---

## ✅ Success Criteria

1. ✅ Screener services only generate candidates
2. ✅ No setup classification in screener stage
3. ✅ No trade plans in screener stage
4. ✅ No recommendations in screener stage
5. ✅ Model validation enforces contract
6. ⏳ Setup classification happens in correct layer
7. ⏳ UI shows appropriate columns per tab
8. ⏳ Full pipeline works end-to-end

---

## 📚 Related Documents

- `docs/SCREENER_CONTRACT.md` - Full contract specification
- `docs/trading_agent_architecture_design.md` - Overall architecture
- `app/services/screeners/` - Screener service implementations
