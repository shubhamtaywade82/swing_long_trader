# Environment Variables Setup Guide

This guide explains how to set up environment variables for the Swing Long Trader system.

## Quick Start

1. Copy the example file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and add your credentials:
   ```bash
   # Required: DhanHQ API credentials
   DHAN_API_KEY=your_dhan_api_key_here
   DHAN_ACCESS_TOKEN=your_dhan_access_token_here
   ```

3. Load environment variables (if using dotenv gem):
   ```bash
   # The dotenv gem automatically loads .env in development/test
   # No manual loading needed
   ```

## Required Variables

### DhanHQ API (Required)

```bash
# DhanHQ API Key (from https://dhan.co/)
DHAN_API_KEY=your_api_key_here

# DhanHQ Access Token (from https://dhan.co/)
DHAN_ACCESS_TOKEN=your_access_token_here
```

**How to get DhanHQ credentials:**
1. Sign up at https://dhan.co/
2. Go to API section
3. Generate API Key and Access Token
4. Copy them to your `.env` file

## Optional Variables

### Telegram Notifications

```bash
# Telegram Bot Token (from @BotFather)
TELEGRAM_BOT_TOKEN=your_bot_token_here

# Telegram Chat ID (your chat ID or channel ID)
TELEGRAM_CHAT_ID=your_chat_id_here
```

**How to get Telegram credentials:**
1. Create a bot via @BotFather on Telegram
2. Get the bot token
3. Start a chat with your bot
4. Get your chat ID from: https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates

### OpenAI Integration

```bash
# OpenAI API Key (for AI ranking)
OPENAI_API_KEY=your_openai_api_key_here
```

**How to get OpenAI API key:**
1. Sign up at https://platform.openai.com/
2. Go to API Keys section
3. Create a new API key
4. Copy it to your `.env` file

### Database Configuration

```bash
# PostgreSQL connection (if different from defaults)
DATABASE_URL=postgresql://user:password@localhost:5432/swing_long_trader
```

### Rails Configuration

```bash
# Rails environment
RAILS_ENV=development

# Secret key base (auto-generated, usually not needed)
SECRET_KEY_BASE=your_secret_key_base_here
```

## Environment-Specific Files

You can create environment-specific files:
- `.env.development` - Development overrides
- `.env.test` - Test overrides
- `.env.production` - Production overrides (never commit!)

## Security Best Practices

1. **Never commit `.env` files:**
   ```bash
   # .env is already in .gitignore
   # Always use .env.example as template
   ```

2. **Use strong, unique values:**
   - Generate secure API keys
   - Use different credentials for dev/test/prod

3. **Rotate credentials regularly:**
   - Update API keys periodically
   - Revoke old keys when rotating

4. **Limit access:**
   - Only share `.env` with trusted team members
   - Use environment variables in production (not files)

## Verification

After setting up `.env`, verify it's loaded:

```bash
# In Rails console
rails console

# Check if variables are loaded
ENV['DHAN_API_KEY']        # Should show your API key
ENV['TELEGRAM_BOT_TOKEN']  # Should show your bot token (if set)
```

## Troubleshooting

### Variables not loading
- Ensure `.env` file exists in project root
- Check file permissions: `ls -la .env`
- Verify dotenv gem is in Gemfile
- Restart Rails server/console after changes

### "API key not configured" errors
- Verify variable names match exactly (case-sensitive)
- Check for extra spaces or quotes in `.env`
- Ensure no trailing spaces after values

### Production deployment
- Use environment variables in your hosting platform
- Never commit `.env` files
- Use platform-specific secret management (AWS Secrets Manager, etc.)

## Example .env File

```bash
# DhanHQ API (Required)
DHAN_API_KEY=abc123xyz789
DHAN_ACCESS_TOKEN=token_abc123xyz789

# Telegram (Optional)
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
TELEGRAM_CHAT_ID=123456789

# OpenAI (Optional)
OPENAI_API_KEY=sk-abc123xyz789

# Database (Optional - uses defaults if not set)
DATABASE_URL=postgresql://user:password@localhost:5432/swing_long_trader

# Rails (Optional)
RAILS_ENV=development
```

