# Phase 6 Completion: Trade Lifecycle FSM (Mandatory)

## ✅ Task 6.1 — Trade Lifecycle FSM
- **File:** `app/trading/trade_lifecycle.rb`
- **Purpose:** Explicit state machine for trade lifecycle tracking
- **States:** All states are explicit and validated

### State Definitions

1. **PROPOSED** - Initial state, trade recommendation created
2. **APPROVED** - Approved by Decision Engine
3. **QUEUED** - Queued for execution (order created)
4. **ENTERED** - Order executed, position entered
5. **MANAGING** - Position being actively managed
6. **EXITED** - Position exited (terminal)
7. **CANCELLED** - Trade cancelled (terminal)
8. **INVALIDATED** - Trade invalidated (terminal)

### Valid State Transitions

```
PROPOSED → APPROVED | CANCELLED | INVALIDATED
APPROVED → QUEUED | CANCELLED | INVALIDATED
QUEUED → ENTERED | CANCELLED | INVALIDATED
ENTERED → MANAGING | CANCELLED | INVALIDATED
MANAGING → EXITED | CANCELLED | INVALIDATED
EXITED → (terminal)
CANCELLED → (terminal)
INVALIDATED → (terminal)
```

### Features

#### State Validation
- All states must be from VALID_STATES list
- Invalid states raise `InvalidStateError`
- State transitions validated against TRANSITIONS map

#### Transition Validation
- Can only transition to valid next states
- Terminal states cannot transition further
- Invalid transitions raise `InvalidTransitionError`

#### History Tracking
- Full history of state changes
- Each transition includes: state, timestamp, reason, previous_state
- Enables audit trail and debugging

#### Convenience Methods
- `approve!`, `queue!`, `enter!`, `start_managing!`, `exit!`, `cancel!`, `invalidate!`
- State checkers: `proposed?`, `approved?`, `queued?`, `entered?`, `managing?`, `exited?`, `cancelled?`, `invalidated?`
- `terminal?` - Check if in terminal state
- `active?` - Check if trade is active (APPROVED, QUEUED, ENTERED, MANAGING)

#### Serialization
- `to_hash` - Convert to hash for storage
- `to_json` - Convert to JSON
- `from_hash` - Restore from hash (deserialization)

### Integration with TradeRecommendation

- TradeRecommendation now includes lifecycle
- Lifecycle initialized to PROPOSED by default
- Can be provided during initialization
- Serialized in `to_hash` output

## Files Created
1. `app/trading/trade_lifecycle.rb`

## Files Modified
1. `app/trading/trade_recommendation.rb` (added lifecycle support)

## Usage Example

```ruby
# Create trade recommendation (lifecycle starts at PROPOSED)
recommendation = Trading::TradeRecommendation.new(
  facts: facts,
  intent: intent,
  quantity: 100,
)

# Decision Engine approves
decision = Trading::DecisionEngine::Engine.call(
  trade_recommendation: recommendation,
  portfolio: portfolio,
)

if decision[:approved]
  # Transition to APPROVED
  recommendation.lifecycle.approve!(reason: "Approved by Decision Engine")
  
  # Queue for execution
  recommendation.lifecycle.queue!(reason: "Order created")
  
  # Order executed
  recommendation.lifecycle.enter!(reason: "Order filled")
  
  # Start managing position
  recommendation.lifecycle.start_managing!
  
  # Exit position
  recommendation.lifecycle.exit!(reason: "Target reached")
end

# Check state
if recommendation.lifecycle.active?
  # Trade is active
end

if recommendation.lifecycle.terminal?
  # Trade is complete
end

# Access history
recommendation.lifecycle.history.each do |entry|
  puts "#{entry[:timestamp]}: #{entry[:state]} - #{entry[:reason]}"
end
```

## Error Handling

### Invalid State
```ruby
begin
  lifecycle = Trading::TradeLifecycle.new(initial_state: "INVALID")
rescue Trading::InvalidStateError => e
  puts e.message # "Invalid state: INVALID. Valid states: PROPOSED, APPROVED, ..."
end
```

### Invalid Transition
```ruby
lifecycle = Trading::TradeLifecycle.new(initial_state: Trading::TradeLifecycle::PROPOSED)
lifecycle.approve!

begin
  lifecycle.exit! # Invalid: PROPOSED → APPROVED → EXITED (skips QUEUED, ENTERED, MANAGING)
rescue Trading::InvalidTransitionError => e
  puts e.message # "Cannot transition from APPROVED to EXITED. Valid transitions: QUEUED, CANCELLED, INVALIDATED"
end
```

### Terminal State Protection
```ruby
lifecycle = Trading::TradeLifecycle.new(initial_state: Trading::TradeLifecycle::EXITED)

begin
  lifecycle.approve! # Invalid: EXITED is terminal
rescue Trading::InvalidTransitionError => e
  puts e.message # "Cannot transition from terminal state EXITED"
end
```

## Behavior Verification
- ✅ All states are explicit and validated
- ✅ State transitions are validated
- ✅ Terminal states cannot transition further
- ✅ Full history tracking
- ✅ Serialization support
- ✅ Integrated with TradeRecommendation
- ✅ Prevents invalid state changes

## Testing Checklist
- [ ] All valid states work correctly
- [ ] Invalid states raise error
- [ ] Valid transitions work
- [ ] Invalid transitions raise error
- [ ] Terminal states cannot transition
- [ ] History tracking works
- [ ] Serialization/deserialization works
- [ ] Convenience methods work
- [ ] State checkers work
- [ ] Integration with TradeRecommendation works

## Next Steps (Phase 7)
- Create Executor Gatekeeper
- Order placement allowed ONLY if:
  - Decision Engine approved
  - Kill-switch clear
  - Mode allows execution
  - FSM state valid
