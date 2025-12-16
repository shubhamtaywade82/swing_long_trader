# Telegram Bots Configuration

**Guide to configuring separate Telegram bots for trading alerts and system alerts**

---

## Overview

The system supports **two separate Telegram bots** to keep trading alerts and system alerts organized:

1. **Trading Bot** - For trading-related notifications (entries, exits, signals, screener results, PnL)
2. **System Bot** - For system-related notifications (errors, job failures, health checks, monitoring)

This separation allows you to:
- Keep trading alerts focused and actionable
- Monitor system health separately
- Configure different notification preferences for each bot
- Use different chat IDs (e.g., personal chat for trading, team channel for system alerts)

---

## Configuration

### Environment Variables

Add the following to your `.env` file:

```bash
# Trading Bot (Trading-related alerts)
TELEGRAM_TRADING_BOT_TOKEN=your_trading_bot_token
TELEGRAM_TRADING_CHAT_ID=your_trading_chat_id

# System Bot (System-related alerts)
TELEGRAM_SYSTEM_BOT_TOKEN=your_system_bot_token
TELEGRAM_SYSTEM_CHAT_ID=your_system_chat_id

# Legacy fallback (optional - used if separate bots not configured)
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=your_chat_id
```

### Configuration File

**File: `config/algo.yml`**

```yaml
notifications:
  # Trading Bot - For trading-related alerts
  telegram_trading:
    enabled: true
    chat_id: <%= ENV['TELEGRAM_TRADING_CHAT_ID'] || ENV['TELEGRAM_CHAT_ID'] %>
    bot_token: <%= ENV['TELEGRAM_TRADING_BOT_TOKEN'] || ENV['TELEGRAM_BOT_TOKEN'] %>
    notify_entry: true
    notify_exit: true
    notify_signals: true
    notify_screener_results: true
    notify_pnl_milestones: true
    pnl_milestones: [5, 10, 15, 20, 30, 50]
    pnl_update_interval_seconds: 3600

  # System Bot - For system-related alerts
  telegram_system:
    enabled: true
    chat_id: <%= ENV['TELEGRAM_SYSTEM_CHAT_ID'] || ENV['TELEGRAM_CHAT_ID'] %>
    bot_token: <%= ENV['TELEGRAM_SYSTEM_BOT_TOKEN'] || ENV['TELEGRAM_BOT_TOKEN'] %>
    notify_errors: true
    notify_job_failures: true
    notify_health_checks: true
    notify_api_errors: true
    notify_system_alerts: true
```

---

## Setting Up Telegram Bots

### Step 1: Create Trading Bot

1. Open Telegram and search for `@BotFather`
2. Send `/newbot` command
3. Follow prompts to create bot:
   - Name: `Swing Trader Trading Bot` (or your preferred name)
   - Username: `your_trading_bot` (must end with `bot`)
4. Copy the bot token (e.g., `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)
5. Set as `TELEGRAM_TRADING_BOT_TOKEN` in `.env`

### Step 2: Create System Bot

1. Repeat steps above with `@BotFather`
2. Create a second bot:
   - Name: `Swing Trader System Bot` (or your preferred name)
   - Username: `your_system_bot` (must end with `bot`)
3. Copy the bot token
4. Set as `TELEGRAM_SYSTEM_BOT_TOKEN` in `.env`

### Step 3: Get Chat IDs

#### For Personal Chat

1. Start a conversation with your bot
2. Send any message (e.g., `/start`)
3. Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
4. Find `"chat":{"id":123456789}` in the response
5. Copy the ID and set as `TELEGRAM_TRADING_CHAT_ID` or `TELEGRAM_SYSTEM_CHAT_ID`

#### For Group/Channel

1. Add bot to group/channel as admin
2. Send a message in the group/channel
3. Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
4. Find the chat ID (may be negative for groups)
5. Copy the ID

---

## Alert Types

### Trading Bot Alerts

The **Trading Bot** sends:

- ✅ **Entry Notifications** - When positions are opened
- ✅ **Exit Notifications** - When positions are closed (with PnL)
- ✅ **Trading Signals** - Generated trading signals
- ✅ **Screener Results** - Daily screener candidate lists
- ✅ **PnL Milestones** - When PnL reaches configured milestones (5%, 10%, 15%, etc.)
- ✅ **Portfolio Snapshots** - Daily portfolio summaries

**Configuration:**
```yaml
telegram_trading:
  notify_entry: true
  notify_exit: true
  notify_signals: true
  notify_screener_results: true
  notify_pnl_milestones: true
  pnl_milestones: [5, 10, 15, 20, 30, 50]
```

### System Bot Alerts

The **System Bot** sends:

- ✅ **Job Failures** - When background jobs fail
- ✅ **API Errors** - When external API calls fail (DhanHQ, OpenAI, etc.)
- ✅ **Health Check Failures** - When system health checks fail
- ✅ **System Errors** - Critical system errors and exceptions
- ✅ **Monitoring Alerts** - System monitoring and metrics alerts
- ✅ **Database Issues** - Database connection or query errors

**Configuration:**
```yaml
telegram_system:
  notify_errors: true
  notify_job_failures: true
  notify_health_checks: true
  notify_api_errors: true
  notify_system_alerts: true
```

---

## How Bot Routing Works

The notifier automatically determines which bot to use based on the alert type:

### Automatic Routing Logic

1. **Trading Alerts** → **Trading Bot** (`:trading`)
   - `send_signal_alert` → Trading Bot
   - `send_exit_alert` → Trading Bot
   - `send_daily_candidates` → Trading Bot
   - `send_tiered_candidates` → Trading Bot
   - `send_portfolio_snapshot` → Trading Bot

2. **System Alerts** → **System Bot** (`:system`)
   - `send_error_alert` → System Bot
   - Job failures (via `JobLogging` concern) → System Bot
   - Health check failures → System Bot
   - API errors → System Bot

### Configuration Resolution Order

When sending a message, the notifier resolves bot configuration in this order:

1. **Check separate bot config** (`telegram_trading` or `telegram_system` in `algo.yml`)
   - If `enabled: true` and both `bot_token` and `chat_id` are present → Use this bot
2. **Fallback to legacy config** (`telegram` in `algo.yml`)
   - If separate bot not configured → Use legacy single bot
3. **Fallback to ENV variables**
   - If config not found → Use `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`

### Implementation Details

**File: `lib/telegram_notifier.rb`**

```ruby
# Automatically routes based on bot_type parameter
TelegramNotifier.send_message(text, bot_type: :trading)  # Uses trading bot
TelegramNotifier.send_message(text, bot_type: :system)   # Uses system bot
TelegramNotifier.send_message(text)                      # Uses legacy/fallback bot
```

**File: `app/services/telegram/notifier.rb`**

```ruby
# Trading alerts automatically use :trading bot
def send_signal_alert(signal)
  send_message(message, bot_type: :trading)  # ← Automatically routes to trading bot
end

# System alerts automatically use :system bot
def send_error_alert(error_message, context: nil)
  send_message(message, bot_type: :system)  # ← Automatically routes to system bot
end
```

## Usage in Code

### Trading Alerts (Automatically routed to Trading Bot)

```ruby
# These automatically use the Trading Bot
Telegram::Notifier.send_signal_alert(signal)
Telegram::Notifier.send_exit_alert(position, exit_reason: "Stop Loss", exit_price: 100.0, pnl: 500.0)
Telegram::Notifier.send_daily_candidates(candidates)
Telegram::Notifier.send_tiered_candidates(final_result)
Telegram::Notifier.send_portfolio_snapshot(portfolio_data)
```

### System Alerts (Automatically routed to System Bot)

```ruby
# These automatically use the System Bot
Telegram::Notifier.send_error_alert("Job failed", context: "SwingScreenerJob")
Telegram::Notifier.send_error_alert("Health check failed", context: "MonitorJob")
Telegram::Notifier.send_error_alert("API error", context: "DhanHQ")
```

### Manual Override (Advanced)

If you need to manually specify which bot to use:

```ruby
# Directly use TelegramNotifier with bot_type
TelegramNotifier.send_message("Custom message", bot_type: :trading)
TelegramNotifier.send_message("Custom message", bot_type: :system)
```

---

## Fallback Behavior

If separate bots are not configured, the system falls back to the legacy single bot configuration:

- Uses `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`
- All alerts (trading + system) go to the same bot
- Maintains backward compatibility

---

## Testing

### Test Trading Bot

```bash
rails console
> Telegram::Notifier.send_signal_alert({
    symbol: "TEST",
    entry_price: 100.0,
    qty: 10,
    stop_loss: 90.0,
    take_profit: 120.0
  })
```

### Test System Bot

```bash
rails console
> Telegram::Notifier.send_error_alert("Test system alert", context: "Test")
```

### Test All Alert Types

```bash
rails test:alerts:all
```

---

## Best Practices

1. **Separate Channels**: Use personal chat for trading bot, team channel for system bot
2. **Mute System Bot**: Consider muting system bot notifications during non-critical hours
3. **Different Priorities**: Configure different notification sounds/priorities for each bot
4. **Backup Configuration**: Keep bot tokens secure and backed up
5. **Regular Testing**: Test both bots regularly to ensure they're working

---

## Troubleshooting

### Bot Not Receiving Messages

1. Verify bot token is correct
2. Verify chat ID is correct
3. Ensure bot is started (send `/start` to bot)
4. Check bot permissions (for groups/channels)

### Messages Not Sending

1. Check `config/algo.yml` - ensure bot is enabled
2. Check environment variables are loaded
3. Check Rails logs for errors
4. Test with `rails console` directly

### Both Bots Using Same Chat

If both bots send to the same chat, check:
- Are `TELEGRAM_TRADING_CHAT_ID` and `TELEGRAM_SYSTEM_CHAT_ID` different?
- Is fallback configuration being used?

---

## Migration from Single Bot

If you're currently using a single bot:

1. Create a second bot for system alerts
2. Add new environment variables
3. Update `config/algo.yml` with new configuration
4. Test both bots
5. Keep legacy configuration for backward compatibility

The system will automatically use separate bots if configured, otherwise falls back to single bot.

---

## Summary

- **Trading Bot**: Trading-related alerts (entries, exits, signals, PnL)
- **System Bot**: System-related alerts (errors, failures, health checks)
- **Fallback**: Single bot if separate bots not configured
- **Configuration**: `config/algo.yml` + environment variables
- **Testing**: Use `rails test:alerts:all` or Rails console
