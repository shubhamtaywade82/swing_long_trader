# Automatic Trading Setup

**Complete guide to automatic trading in both paper and live modes with balance checking**

---

## Overview

The system now supports **fully automatic trading** in both paper trading and live trading modes. When balance is insufficient, Telegram notifications are sent automatically.

---

## What's Enabled

### ✅ Automatic Features

1. **Automatic Screening** - Runs daily at 07:40 IST
2. **Automatic Signal Generation** - After screening (if `auto_analyze: true`)
3. **Automatic Entry Monitoring** - Every 30 minutes during market hours (9 AM - 3:30 PM IST)
4. **Automatic Exit Monitoring** - Every 30 minutes during market hours
5. **Balance Checking** - Before every trade (both paper and live)
6. **Telegram Notifications** - When balance is insufficient

---

## Configuration

### 1. Enable Automatic Trading

**File: `config/algo.yml`**

```yaml
execution:
  # Automatic trading - enables fully automated trading
  auto_trading:
    enabled: true  # ✅ Set to true for automatic trading

  # Manual approval (only applies if auto_trading.enabled is false)
  manual_approval:
    enabled: false  # Disabled when auto_trading is enabled
    count: 30
```

### 2. Enable Automatic Analysis

**File: `config/algo.yml`**

```yaml
swing_trading:
  strategy:
    auto_analyze: true  # ✅ Automatically analyze candidates after screening
```

### 3. Scheduled Jobs (Already Enabled)

**File: `config/recurring.yml`**

```yaml
production:
  # Entry monitoring - Every 30 minutes during market hours
  swing_entry_monitor:
    class: Strategies::Swing::EntryMonitorJob
    schedule: "*/30 9-15 * * 1-5"  # 9 AM - 3:30 PM IST, weekdays

  # Exit monitoring - Every 30 minutes during market hours
  swing_exit_monitor:
    class: Strategies::Swing::ExitMonitorJob
    schedule: "*/30 9-15 * * 1-5"  # 9 AM - 3:30 PM IST, weekdays
```

---

## Balance Checking

### Paper Trading Mode

**How it works:**
- Checks `PaperPortfolio.available_capital` before each trade
- If insufficient, sends Telegram notification and skips trade
- Notification includes:
  - Required amount
  - Available balance
  - Shortfall amount
  - Symbol and order details

**Example Telegram Notification:**
```
📊 PAPER TRADING RECOMMENDATION

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📈 Signal Details:
Symbol: RELIANCE
Direction: LONG
Entry Price: ₹2,500.00
Quantity: 20
Order Value: ₹50,000.00
Stop Loss: ₹2,300.00
Take Profit: ₹2,875.00
Confidence: 85.5%
Risk-Reward: 2.5:1
Est. Holding: 12 days

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💰 Portfolio Balance:
Required: ₹50,000.00
Available: ₹25,000.00
Shortfall: ₹25,000.00

Portfolio: default
Total Equity: ₹75,000.00
Capital: ₹25,000.00

⚠️ Trade Not Executed - Insufficient balance

💡 Add ₹25,000.00 to portfolio to execute this trade.
```

### Live Trading Mode

**How it works:**
- Checks DhanHQ account balance via API before each trade
- If insufficient, sends Telegram notification and skips trade
- Uses `Dhan::Balance.check_available_balance` service
- Notification includes:
  - Required amount
  - Available balance
  - Shortfall amount
  - Symbol and order details

**Example Telegram Notification:**
```
📊 TRADING RECOMMENDATION

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📈 Signal Details:
Symbol: RELIANCE
Direction: LONG
Entry Price: ₹2,500.00
Quantity: 20
Order Value: ₹50,000.00
Stop Loss: ₹2,300.00
Take Profit: ₹2,875.00
Confidence: 85.5%
Risk-Reward: 2.5:1
Est. Holding: 12 days

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💰 Balance Information:
Required: ₹50,000.00
Available: ₹25,000.00
Shortfall: ₹25,000.00

⚠️ Trade Not Executed - Insufficient balance

💡 Add ₹25,000.00 to your account to execute this trade.
```

---

## How It Works

### Complete Flow

```
07:40 IST - Swing Screener Runs
├─ Analyzes instruments
├─ Finds top candidates
└─ Triggers AnalysisJob (if auto_analyze: true)

AnalysisJob Runs
├─ Evaluates candidates
├─ Generates trading signals
└─ Signals ready for execution

Every 30 Minutes (9 AM - 3:30 PM IST) - Entry Monitor Runs
├─ Checks top candidates for entry conditions
├─ Generates signals if conditions met
├─ Checks balance (paper or live)
│  ├─ If sufficient → Executes trade
│  └─ If insufficient → Sends Telegram notification, skips trade
└─ Logs results

Every 30 Minutes (9 AM - 3:30 PM IST) - Exit Monitor Runs
├─ Checks open positions
├─ Triggers exits if stop loss/take profit hit
└─ Executes exit orders
```

---

## Balance Check Implementation

### Paper Trading

**Service:** `PaperTrading::RiskManager.check_capital_available`

**Checks:**
- `portfolio.available_capital >= required_capital`
- Sends notification if insufficient

**Location:** `app/services/paper_trading/risk_manager.rb`

### Live Trading

**Service:** `Dhan::Balance.check_available_balance`

**Checks:**
- DhanHQ API account balance
- Sends notification if insufficient

**Location:** `app/services/dhan/balance.rb`

**Note:** The DhanHQ balance check uses the DhanHQ API. You may need to adjust the API method name based on your DhanHQ client implementation. The service tries multiple common method names:
- `get_fund_limits`
- `get_account_balance`
- `get_margin`

---

## Testing

### Test Paper Trading Balance Check

```bash
rails console

# Create a portfolio with low balance
portfolio = PaperPortfolio.find_or_create_by(name: "test")
portfolio.update!(capital: 1000, available_capital: 1000)

# Try to place a trade requiring more capital
signal = {
  instrument_id: Instrument.first.id,
  entry_price: 100,
  qty: 20,  # Requires ₹2,000
  direction: :long
}

result = PaperTrading::Executor.execute(signal, portfolio: portfolio)
# Should return error and send Telegram notification
```

### Test Live Trading Balance Check

```bash
rails console

# Check balance
result = Dhan::Balance.check_available_balance
puts "Balance: ₹#{result[:balance]}" if result[:success]

# Try to place a trade
signal = {
  instrument_id: Instrument.first.id,
  entry_price: 100,
  qty: 20,
  direction: :long
}

result = Strategies::Swing::Executor.call(signal)
# Will check balance and send notification if insufficient
```

---

## Monitoring

### Check Balance Status

```bash
# Paper trading
rails console
> portfolio = PaperPortfolio.find_by(name: "default")
> puts "Available: ₹#{portfolio.available_capital}"
> puts "Total Equity: ₹#{portfolio.total_equity}"

# Live trading
rails console
> result = Dhan::Balance.check_available_balance
> puts "Balance: ₹#{result[:balance]}" if result[:success]
```

### View Failed Trades Due to Balance

```bash
rails console

# Paper trading - check logs for balance errors
# Check Telegram for notifications

# Live trading - check order records
> Order.where("error_message LIKE ?", "%Insufficient balance%")
```

---

## Troubleshooting

### Balance Check Not Working

**Issue:** Balance check always fails

**Solution:**
1. Check DhanHQ API credentials in `.env`
2. Verify DhanHQ client is properly initialized
3. Check API method names in `app/services/dhan/balance.rb`
4. Review logs: `tail -f log/development.log | grep Balance`

### Telegram Notifications Not Sending

**Issue:** No notifications when balance is insufficient

**Solution:**
1. Check Telegram configuration in `config/algo.yml`
2. Verify `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in `.env`
3. Test Telegram: `rails runner "Telegram::Notifier.send_error_alert('Test', context: 'Test')"`

### Automatic Trading Not Working

**Issue:** Trades still require manual approval

**Solution:**
1. Check `config/algo.yml`: `execution.auto_trading.enabled: true`
2. Verify `config/recurring.yml` has entry/exit monitors enabled
3. Restart SolidQueue worker: `bin/rails solid_queue:start`
4. Check job logs: `tail -f log/development.log | grep EntryMonitor`

---

## Safety Features

### Risk Management Still Active

Even with automatic trading enabled, the following safety checks remain:

1. **Position Size Limits** - Max 10% per position (configurable)
2. **Total Exposure Limits** - Max 50% total exposure (configurable)
3. **Daily Loss Limits** - Stops trading if daily loss exceeds limit
4. **Circuit Breaker** - Stops trading if failure rate > 50%
5. **Balance Checks** - Prevents trades when insufficient funds

### Manual Override

You can still:
- Manually approve/reject orders via Rails console
- Disable automatic trading by setting `auto_trading.enabled: false`
- Stop all trading by stopping SolidQueue workers

---

## Configuration Summary

### Required Settings for Automatic Trading

```yaml
# config/algo.yml
execution:
  auto_trading:
    enabled: true

swing_trading:
  strategy:
    auto_analyze: true
```

### Already Configured

- ✅ Entry monitor job scheduled
- ✅ Exit monitor job scheduled
- ✅ Balance checking implemented
- ✅ Telegram notifications configured

---

## Next Steps

1. **Test in Paper Trading Mode First**
   - Enable paper trading: `paper_trading.enabled: true`
   - Monitor for a few days
   - Verify balance checks work correctly

2. **Test Balance Notifications**
   - Create low balance scenario
   - Verify Telegram notifications are sent
   - Check notification content

3. **Enable Live Trading**
   - After paper trading validation
   - Set `paper_trading.enabled: false`
   - Monitor closely for first week

4. **Monitor Performance**
   - Check balance regularly
   - Review failed trades due to balance
   - Adjust risk limits if needed

---

**Remember:** Automatic trading is now enabled. The system will:
- ✅ Trade automatically in both paper and live modes
- ✅ Check balance before every trade
- ✅ Send Telegram notifications when balance is insufficient
- ✅ Skip trades when balance is too low

**Stay vigilant and monitor your account balance regularly!**
