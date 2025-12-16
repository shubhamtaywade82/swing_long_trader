# Verification Checklist After Trading Agent Architecture Changes

## ✅ Critical Checks

### 1. Zeitwerk Autoloading
```bash
rails zeitwerk:check
```
**Expected:** `All is good!`
**Status:** ✅ PASSED

### 2. Class Loading
```bash
rails runner "puts Trading::Config.class.name; puts Trading::Orchestrator.class.name; puts Llm::ReviewService.class.name"
```
**Expected:** All classes should load without errors
**Status:** ✅ VERIFIED

### 3. File Locations
- ✅ `app/services/trading/` - Trading Agent system (moved from `app/trading/`)
- ✅ `app/models/llm/` - LLM review services (moved from `app/llm/`)
- ✅ `app/services/screeners/ai_evaluator.rb` - AI evaluator (kept, not renamed)
- ✅ `app/services/market_hub/ltp_pub_sub_listener.rb` - Pub/Sub listener (kept, not renamed)
- ✅ `app/services/portfolio_services/` - Portfolio services (not `app/services/portfolio/`)

---

## 🔧 Configuration Checks

### 4. Trading Configuration
**File:** `config/trading.yml`

**Check:**
- Feature flags are set correctly:
  - `dto_enabled: false` (default - disabled until ready)
  - `decision_engine.enabled: false` (default - disabled)
  - `llm.enabled: false` (default - disabled)
  - `modes.current: "advisory"` (default - advisory mode)

**To Enable Trading Agent:**
```yaml
trading:
  dto_enabled: true
  decision_engine:
    enabled: true
```

---

## 🔄 Integration Points

### 5. Screener Integration
**File:** `app/services/screeners/final_selector.rb`

**Check:**
- Trading Agent integration is conditional on feature flags
- Falls back gracefully if Trading Agent fails
- Only processes candidates when `dto_enabled` AND `decision_engine_enabled` are true

**Test:**
```ruby
# In Rails console
screener_result = ScreenerResult.last
result = Trading::Orchestrator.process_screener_result(screener_result, portfolio: nil, mode: "advisory", dry_run: true)
puts result
```

### 6. Decision Engine
**File:** `app/services/trading/decision_engine/engine.rb`

**Check:**
- Validates trade recommendations
- Checks risk rules, portfolio constraints, setup quality
- Returns approval/rejection with reasons

**Test:**
```ruby
# Create a test recommendation
recommendation = Trading::TradeRecommendation.new(...)
result = Trading::DecisionEngine::Engine.call(trade_recommendation: recommendation, portfolio: nil)
puts result[:approved] # Should be true/false
```

---

## 📊 Database Schema

### 7. Migration Status
**Check if migration was removed:**
- `db/migrate/20251215000001_add_atr_based_fields_to_positions.rb` was deleted
- If you need ATR fields, you'll need to add them back

**Check current schema:**
```bash
rails db:schema:dump
grep -i "tp1\|tp2\|atr" db/schema.rb
```

**Note:** The branch removed ATR-based fields. If you need them:
- Re-add the migration
- Re-add the Position model methods
- Re-add the exit monitor job logic

---

## 🧪 Testing Checklist

### 8. Basic Functionality Tests

#### A. Trading Agent Classes Load
```ruby
rails runner "
  puts Trading::Config.class.name
  puts Trading::Orchestrator.class.name
  puts Trading::Executor.class.name
  puts Trading::DecisionEngine::Engine.class.name
  puts Llm::ReviewService.class.name
"
```

#### B. Configuration Access
```ruby
rails runner "
  puts Trading::Config.dto_enabled?
  puts Trading::Config.decision_engine_enabled?
  puts Trading::Config.current_mode
"
```

#### C. Screener Integration
```ruby
# In Rails console
screener_result = ScreenerResult.where(screener_type: 'swing').last
if screener_result
  result = Trading::Orchestrator.process_screener_result(
    screener_result,
    portfolio: nil,
    mode: 'advisory',
    dry_run: true
  )
  puts result.inspect
end
```

#### D. Decision Engine (if enabled)
```ruby
# This will fail if feature flags are disabled (expected)
# Enable in config/trading.yml first
Trading::Config.dto_enabled? && Trading::Config.decision_engine_enabled?
```

---

## ⚠️ Breaking Changes

### 9. Removed Features
The branch **removed** ATR-based trading features:
- ❌ TP1/TP2 targets
- ❌ ATR-based stop loss multipliers
- ❌ Breakeven stop after TP1
- ❌ ATR-based trailing stops
- ❌ RSI recovery momentum check

**If you need these features:**
- They were in the `cursor/swing-trading-strategy-implementation-6b67` branch
- You may need to cherry-pick those changes back

### 10. Position Model Changes
**Removed methods:**
- `check_tp1_hit?`
- `check_tp2_hit?`
- `move_stop_to_breakeven!`
- `check_atr_trailing_stop?`

**Removed fields (if migration was run):**
- `tp1`, `tp2`, `atr`, `atr_pct`, `tp1_hit`, `breakeven_stop`, `atr_trailing_multiplier`, `initial_stop_loss`

---

## 🔍 Code References

### 11. Namespace References
**Check these are correct:**
- ✅ `Screeners::AIEvaluator` (not `AIRanker`)
- ✅ `Trading::*` (all trading agent classes)
- ✅ `Llm::*` (LLM review classes)
- ✅ `PortfolioServices::*` (not `Portfolio::*` for services)

**Files to verify:**
- `app/jobs/screeners/swing_screener_job.rb` - Uses `AIEvaluator.call`
- `app/services/screeners/final_selector.rb` - Uses `Trading::Orchestrator`
- `app/trading/decision_engine/engine.rb` - Uses `Llm::ReviewService`

---

## 📝 Documentation

### 12. New Documentation Files
**Check these exist:**
- `docs/trading_agent_architecture_design.md` - Architecture overview
- `docs/trading_agent_implementation_complete.md` - Implementation details
- `docs/wiring_fixes_complete.md` - Integration fixes
- `docs/phase_0_system_map.md` through `phase_8_completion.md` - Phase documentation

---

## 🚀 Next Steps

### 13. Enable Trading Agent (When Ready)
1. **Update `config/trading.yml`:**
   ```yaml
   trading:
     dto_enabled: true
     decision_engine:
       enabled: true
   ```

2. **Test in advisory mode first:**
   - Mode: `advisory` (recommendations only, no execution)
   - Verify Decision Engine approvals/rejections
   - Check audit logs

3. **Gradually enable execution:**
   - Start with `semi_automated` mode
   - Require manual approval
   - Monitor for issues

4. **Full automation (if desired):**
   - Enable `fully_automated` mode
   - Set kill switches appropriately
   - Monitor closely

---

## 🐛 Common Issues

### Issue: `Portfolio::CapitalBucketer` error
**Fix:** Use `PortfolioServices::CapitalBucketer` (Portfolio is a model, not a module)

### Issue: Trading Agent not processing
**Check:** Feature flags in `config/trading.yml` must be enabled

### Issue: Zeitwerk errors
**Fix:** Ensure files are in correct locations:
- `app/services/trading/` (not `app/trading/`)
- `app/models/llm/` (not `app/llm/`)

### Issue: Missing ATR features
**Note:** These were intentionally removed. Re-add from previous branch if needed.

---

## ✅ Quick Verification Script

Run this in Rails console:
```ruby
# 1. Check classes load
puts "✅ Trading::Config: #{Trading::Config.class.name}"
puts "✅ Trading::Orchestrator: #{Trading::Orchestrator.class.name}"
puts "✅ Llm::ReviewService: #{Llm::ReviewService.class.name}"
puts "✅ Screeners::AIEvaluator: #{Screeners::AIEvaluator.class.name}"

# 2. Check configuration
puts "\n📋 Configuration:"
puts "  DTO Enabled: #{Trading::Config.dto_enabled?}"
puts "  Decision Engine Enabled: #{Trading::Config.decision_engine_enabled?}"
puts "  Current Mode: #{Trading::Config.current_mode}"

# 3. Check integration point
puts "\n🔗 Integration:"
puts "  FinalSelector has Trading Agent: #{Screeners::FinalSelector.instance_methods.include?(:process_through_trading_agent)}"

puts "\n✅ All checks passed!"
```
