# Environment Variables

## Required Variables

### DhanHQ API
```bash
DHANHQ_CLIENT_ID=your_client_id
DHANHQ_ACCESS_TOKEN=your_access_token
```

**Alternative names (for backward compatibility):**
```bash
CLIENT_ID=your_client_id
ACCESS_TOKEN=your_access_token
```

## Optional Variables

### Telegram Notifications
```bash
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=your_chat_id
```

### OpenAI (for AI Ranking)
```bash
OPENAI_API_KEY=your_openai_api_key
```

### DhanHQ Configuration
```bash
DHANHQ_BASE_URL=https://api.dhan.co  # Default
DHAN_LOG_LEVEL=INFO                  # Default
DHAN_API_TYPE=option_chain           # Default
```

### Backtesting
```bash
BACKTEST_INITIAL_CAPITAL=100000      # Default: 100000
BACKTEST_RISK_PER_TRADE=2.0          # Default: 2.0
```

### Execution (Phase 12)
```bash
DRY_RUN=true                         # Default: false (set to true to disable real orders)
```

### Rails Configuration
```bash
RAILS_ENV=development                 # development, test, production
RAILS_LOG_LEVEL=info                  # debug, info, warn, error
```

## Setup

1. Copy `.env.example` to `.env`
2. Fill in required variables
3. Restart Rails server/jobs for changes to take effect

## Security Notes

- Never commit `.env` file to git
- Use environment-specific values for production
- Rotate API keys regularly
- Use secrets management in production (AWS Secrets Manager, etc.)

