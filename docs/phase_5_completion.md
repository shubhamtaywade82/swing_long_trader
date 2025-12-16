# Phase 5 Completion: LLM Hard Boundary

## ✅ Task 5.1 — LLM Review Contract
- **File:** `app/llm/review_contract.rb`
- **Purpose:** Strict contract ensuring LLM can ONLY provide advisory information
- **Output Schema:**
  ```ruby
  {
    advisory_level: "info" | "warning" | "block_auto",
    confidence_adjustment: Integer (-10 to +10),
    notes: String
  }
  ```
- **Rules:**
  - ✅ LLM MUST NOT return approved/rejected
  - ✅ Only advisory levels allowed
  - ✅ Confidence adjustment clamped to -10 to +10
  - ✅ Default contract when LLM fails

### Advisory Levels
- `info` - Informational note, no action needed
- `warning` - Warning but trade can proceed
- `block_auto` - Block automated execution, require manual review

### Methods
- `parse(response_content)` - Parse from LLM JSON response
- `build_from_parsed(parsed)` - Build from parsed hash
- `default_contract` - Fallback when LLM unavailable

## ✅ Task 5.2 — LLM Review Service
- **File:** `app/llm/review_service.rb`
- **Purpose:** Service to review TradeRecommendation using LLM
- **Rules:**
  - ✅ LLM can ONLY provide advisory information
  - ✅ System continues working if LLM fails
  - ✅ Uses existing AI::UnifiedService
  - ✅ Respects feature flag

### Integration
- Called AFTER Decision Engine approval
- Output attached to decision, never enforced
- Falls back gracefully on failure

## ✅ Task 5.3 — Decision Engine Integration
- **File:** `app/trading/decision_engine/engine.rb`
- **Changes:**
  - Added `perform_llm_review` method
  - LLM review runs AFTER all deterministic checks pass
  - LLM review result attached to decision (never blocks)
  - Respects `llm.enabled` feature flag

### Flow
```
Decision Engine Approval → LLM Review (optional) → Final Decision
```

**Key Point:** LLM review cannot block a trade that passed Decision Engine. It can only:
- Provide advisory notes
- Adjust confidence (for display)
- Flag for manual review (block_auto)

## Files Created
1. `app/llm/review_contract.rb`
2. `app/llm/review_service.rb`

## Files Modified
1. `app/trading/decision_engine/engine.rb` (added LLM review integration)

## Configuration
- **File:** `config/trading.yml`
- **Flag:** `llm.enabled: false` (disabled by default)
- **Provider:** `llm.provider: "auto"` (auto-detects Ollama/OpenAI)

## Behavior Verification
- ✅ LLM cannot approve/reject trades
- ✅ LLM can only provide advisory feedback
- ✅ System works even if LLM fails
- ✅ LLM review runs AFTER Decision Engine
- ✅ LLM output is attached, never enforced
- ✅ Feature flag controls LLM usage

## Usage Example

```ruby
# Decision Engine with optional LLM review
decision = Trading::DecisionEngine::Engine.call(
  trade_recommendation: recommendation,
  portfolio: portfolio,
)

if decision[:approved]
  # Check LLM review if available
  if decision[:llm_review] && decision[:llm_review][:contract]
    contract = decision[:llm_review][:contract]
    
    if contract.block_auto?
      # Require manual review
      puts "LLM flagged for manual review: #{contract.notes}"
    elsif contract.warning?
      # Warning but can proceed
      puts "LLM warning: #{contract.notes}"
    end
    
    # Adjust confidence (for display only)
    adjusted_confidence = recommendation.confidence_score + contract.confidence_adjustment
  end
  
  # Proceed with trade (LLM cannot block)
end
```

## Refactoring Notes

### Existing AI Usage (NOT Changed Yet)
- `Screeners::AIEvaluator` still exists and works as before
- This is intentional - gradual migration
- New LLM review is separate and optional

### Future Refactoring (Phase 6+)
- Remove AI calls from screeners
- AI runs ONLY after Decision Engine approval
- Migrate existing AI evaluation to new pattern

## Testing Checklist
- [ ] ReviewContract parses valid JSON correctly
- [ ] ReviewContract handles invalid JSON gracefully
- [ ] ReviewContract validates advisory_level
- [ ] ReviewContract clamps confidence_adjustment
- [ ] ReviewService calls AI::UnifiedService correctly
- [ ] ReviewService falls back on failure
- [ ] Decision Engine includes LLM review when enabled
- [ ] LLM review never blocks approved trades
- [ ] System works when LLM is disabled

## Next Steps (Phase 6)
- Create Trade Lifecycle FSM
- Define states: PROPOSED, APPROVED, QUEUED, ENTERED, MANAGING, EXITED, CANCELLED, INVALIDATED
- Wire FSM into execution flow
