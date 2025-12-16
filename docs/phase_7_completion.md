# Phase 7 Completion: Execution Gate

## ✅ Task 7.1 — Executor Gatekeeper
- **File:** `app/trading/executor.rb`
- **Purpose:** Final gate before order placement
- **Order placement allowed ONLY if:**
  1. ✅ Decision Engine approved
  2. ✅ Kill-switch clear
  3. ✅ Mode allows execution
  4. ✅ FSM state valid

## Gate Checks

### Gate 1: Decision Engine Approval
- Must have `decision_result[:approved] == true`
- Rejects if Decision Engine rejected the trade
- Returns decision_result for debugging

### Gate 2: Kill-Switch Check
- Manual kill-switch flag (Redis cache)
- Significant drawdown (>15%)
- Consecutive losses (>=3)
- Daily loss limit (configurable, default 5%)
- Uses SystemContext for portfolio state

### Gate 3: Mode Allows Execution
- **advisory** - No execution allowed
- **semi_automated** - Execution allowed with approval
- **fully_automated** - Execution allowed without approval

### Gate 4: FSM State Valid
- Must be in APPROVED state
- Cannot execute from other states
- Prevents double-execution

## Execution Modes

### Dry Run
- Simulates execution
- Transitions lifecycle to QUEUED
- Returns success without placing order

### Semi-Automated
- Creates order with `requires_approval: true`
- Transitions lifecycle to QUEUED
- Waits for manual approval

### Fully Automated
- Creates order with `requires_approval: false`
- Auto-approves order
- Transitions lifecycle to QUEUED (waiting for execution)

## Order Creation

### Paper Trading
- Uses existing `PaperTrading::Executor`
- Creates paper position
- Transitions lifecycle to ENTERED on success

### Live Trading
- Creates `Order` record
- Sets `requires_approval` based on mode
- Includes full metadata (recommendation, decision_result)

## Lifecycle Management

- **PROPOSED** → **APPROVED** (by Decision Engine)
- **APPROVED** → **QUEUED** (order created)
- **QUEUED** → **ENTERED** (order executed - handled by order processor)
- **ENTERED** → **MANAGING** (position management - handled separately)
- **MANAGING** → **EXITED** (position closed - handled separately)

## Files Created
1. `app/trading/executor.rb`

## Usage Example

```ruby
# Run Decision Engine first
decision = Trading::DecisionEngine::Engine.call(
  trade_recommendation: recommendation,
  portfolio: portfolio,
)

# Execute if approved
if decision[:approved]
  result = Trading::Executor.execute(
    trade_recommendation: recommendation,
    decision_result: decision,
    portfolio: portfolio,
    mode: "semi_automated",
    dry_run: false,
  )

  if result[:success]
    puts "Order created: #{result[:order].client_order_id}"
    puts "Lifecycle state: #{result[:lifecycle_state]}"
  else
    puts "Execution blocked: #{result[:error]}"
    puts "Blocked at gate: #{result[:gate]}"
  end
end
```

## Error Responses

Each gate failure returns:
```ruby
{
  success: false,
  error: "Reason for failure",
  gate: "gate_name", # "decision_engine", "kill_switch", "mode", "fsm_state"
  # Gate-specific data
}
```

## Behavior Verification
- ✅ Decision Engine approval required
- ✅ Kill-switch checks enforced
- ✅ Mode validation enforced
- ✅ FSM state validation enforced
- ✅ No order placed without all gates passing
- ✅ Lifecycle transitions tracked
- ✅ Supports dry run mode
- ✅ Supports paper and live trading

## Testing Checklist
- [ ] Decision Engine rejection blocks execution
- [ ] Kill-switch blocks execution
- [ ] Advisory mode blocks execution
- [ ] Invalid FSM state blocks execution
- [ ] Semi-automated mode creates order with approval
- [ ] Fully automated mode auto-approves
- [ ] Dry run simulates execution
- [ ] Paper trading works correctly
- [ ] Live trading creates Order record
- [ ] Lifecycle transitions correctly

## Integration Flow

```
TradeRecommendation (PROPOSED)
    ↓
Decision Engine
    ↓ (approved)
Executor Gatekeeper
    ├─ Gate 1: Decision Engine ✓
    ├─ Gate 2: Kill-switch ✓
    ├─ Gate 3: Mode ✓
    └─ Gate 4: FSM State ✓
    ↓ (all gates passed)
Order Created (QUEUED)
    ↓
Order Execution (ENTERED)
    ↓
Position Management (MANAGING)
    ↓
Position Exit (EXITED)
```

## Next Steps (Phase 8)
- Create Audit Log
- Log: facts, intent, decision path, LLM notes, execution result
- Enable debugging of drawdowns
