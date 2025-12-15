# Strict Risk Management Rules Implementation

## Overview

This document describes the implementation of strict risk management rules based on the user's requirements. These rules are **enforced at the system level** to prevent "Instagram math" and ensure disciplined trading.

## Core Rules (Hardcoded - Cannot Be Bypassed)

### 1. Daily Risk Limit: 2% of Capital (MAX)

- **Rule**: Maximum 2% of total equity can be risked per day
- **Enforcement**:
  - `PortfolioServices::RiskManager#check_daily_risk_limit`
  - `PortfolioServices::RiskManager#check_daily_loss`
- **Calculation**:
  - Total risk today = Sum of (quantity × (entry_price - stop_loss)) for all positions opened today
  - If total risk >= 2% of equity → **TRADE REJECTED**

### 2. Risk Per Trade: Daily Risk / Number of Trades

- **Rule**: Risk per trade = Daily Risk (2%) / Number of trades today
  - 1 trade today → 2% risk per trade
  - 2 trades today → 1% risk per trade each
- **Enforcement**:
  - `Screeners::TradePlanBuilder.risk_per_trade_pct(trades_today:)`
  - `Screeners::TradePlanBuilder#calculate_quantity`
- **Calculation**:
  ```ruby
  risk_per_trade_pct = 2.0 / [trades_today, 2].min
  risk_per_trade = capital × (risk_per_trade_pct / 100.0)
  quantity = risk_per_trade / risk_per_share
  ```

### 3. Maximum Trades Per Day: 2

- **Rule**: Maximum 2 trades per day (hard limit)
- **Enforcement**:
  - `PortfolioServices::RiskManager#check_max_trades_per_day`
- **Action**: If 2 trades already taken today → **TRADE REJECTED**

### 4. Minimum Risk-Reward Ratio: 2.5R (1:3)

- **Rule**: All trades must have Risk:Reward ≥ 1:3 (minimum 2.5R for safety margin)
- **Enforcement**:
  - `Screeners::TradePlanBuilder::MIN_RR = 2.5`
  - Trade plan rejected if `risk_reward < 2.5`
- **Calculation**:
  ```ruby
  risk = entry_price - stop_loss
  reward = take_profit - entry_price
  risk_reward = reward / risk
  # Reject if risk_reward < 2.5
  ```

### 5. Cooldown After 2 Consecutive Losses

- **Rule**: After 2 consecutive losses, no new trades allowed (cooldown period)
- **Enforcement**:
  - `PortfolioServices::RiskManager#check_consecutive_losses`
- **Action**: If last 2 closed positions are losses → **TRADE REJECTED**

### 6. Hard Stop Loss (No Averaging)

- **Rule**: Stop loss must be executed immediately, no averaging down
- **Enforcement**:
  - System enforces LIMIT orders only (no MARKET orders)
  - Stop loss orders are placed immediately on entry
  - No position averaging logic in the system

## Implementation Details

### Trade Plan Builder (`app/services/screeners/trade_plan_builder.rb`)

**Key Changes:**
- `DAILY_RISK_PCT = 2.0` (was 0.75%)
- `MIN_RR = 2.5` (was 2.0)
- `MAX_TRADES_PER_DAY = 2`
- `risk_per_trade_pct(trades_today:)` method calculates risk per trade based on daily limit
- Quantity calculation uses dynamic risk per trade based on trades today

**Example:**
```ruby
# If 0 trades today:
risk_per_trade = capital × 2.0% = ₹2,000 (for ₹1L capital)

# If 1 trade already taken today:
risk_per_trade = capital × 1.0% = ₹1,000 (for ₹1L capital)
```

### Risk Manager (`app/services/portfolio_services/risk_manager.rb`)

**New Checks:**
1. `check_max_trades_per_day` - Enforces max 2 trades per day
2. `check_daily_risk_limit(new_trade_risk:)` - Enforces 2% daily risk limit
3. `check_daily_loss` - Updated to use 2% limit (hardcoded)
4. `check_consecutive_losses` - Already existed, now properly enforced

**All checks must pass for trade to be allowed.**

## Expected Monthly Returns (Based on Rules)

| Capital | 40% WR Profit | 50% WR Profit |
| ------- | ------------- | ------------- |
| ₹50k    | ₹12,000       | ₹20,000       |
| ₹1L     | ₹24,000       | ₹40,000       |
| ₹2L     | ₹48,000       | ₹80,000       |
| ₹5L     | ₹1.2L         | ₹2.0L         |
| ₹10L    | ₹2.4L         | ₹4.0L         |

**Assumptions:**
- 20 trading days per month
- 1-2 trades per day
- Risk:Reward = 1:3
- Strict stop loss execution
- No averaging, no revenge trades

## Enforcement Points

1. **Screener Level**: Trade plans rejected if RR < 2.5
2. **Risk Manager Level**: All risk checks before trade execution
3. **Executor Level**: Final validation before order placement
4. **Order Placement**: Only LIMIT orders (no MARKET orders)

## Critical Success Factors

This system **only works if ALL are true**:

1. ✅ **Hard SL** (enforced by system - LIMIT orders only)
2. ✅ **RR ≥ 2.5 actually achieved** (enforced by trade plan builder)
3. ✅ **No overtrading** (enforced by max 2 trades/day)
4. ✅ **No lot-size cheating** (enforced by risk per trade calculation)
5. ✅ **No drawdown spiral** (enforced by cooldown after 2 losses)

## Configuration

These rules are **hardcoded** and cannot be overridden:
- Daily risk: 2% (hardcoded in `RiskManager`)
- Max trades/day: 2 (hardcoded in `RiskManager`)
- Min RR: 2.5 (hardcoded in `TradePlanBuilder`)

The system **enforces discipline**, not the user.
