# 🚀 Next Steps - Swing Long Trader Setup

**Current Status:** ✅ Migrations completed, foundation files copied and cleaned

---

## 📋 Immediate Next Steps (Priority Order)

### Step 1: Install Required Gems ✅ (Just Added)

**Gems added to Gemfile:**
- ✅ `DhanHQ` - Trading API client
- ✅ `telegram-bot-ruby` - Notifications
- ✅ `ruby-technical-analysis` & `technical-analysis` - Technical indicators
- ✅ `activerecord-import` - Bulk database operations
- ✅ `rack-cors` - CORS support
- ✅ `concurrent-ruby` - Concurrency utilities
- ✅ `dotenv-rails` - Environment variables

**Action Required:**
```bash
bundle install
```

---

### Step 2: Create Environment Variables Template

**Create `.env.example`:**
```bash
# DhanHQ API Credentials
DHANHQ_CLIENT_ID=your_client_id_here
DHANHQ_ACCESS_TOKEN=your_access_token_here
# OR use legacy names
CLIENT_ID=your_client_id_here
ACCESS_TOKEN=your_access_token_here

# Telegram Notifications
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here

# Rails Configuration
RAILS_ENV=development
RAILS_LOG_LEVEL=info

# Optional: DhanHQ Configuration
DHANHQ_BASE_URL=https://api.dhan.co
DHAN_LOG_LEVEL=INFO
```

**Action Required:**
- Copy `.env.example` to `.env` and fill in your credentials
- Add `.env` to `.gitignore` (if not already)

---

### Step 3: Test Instrument Import

**Import instruments from DhanHQ:**
```bash
# Import instruments (downloads CSV and imports to database)
rails instruments:import

# Check import status
rails instruments:status

# Verify instruments were imported
rails runner "puts 'Instruments: ' + Instrument.count.to_s"
rails runner "puts 'NIFTY: ' + (Instrument.find_by(symbol_name: 'NIFTY') ? 'Found' : 'Not found')"
```

**Expected Result:**
- Instruments table populated with equity and index instruments
- NIFTY, BANKNIFTY, SENSEX should be available
- No derivatives (swing trading doesn't need them)

---

### Step 4: Verify Core Functionality

**Test Rails console loads:**
```bash
rails console
```

**In console, test:**
```ruby
# Test models load
Instrument.first
CandleSeries.first
Setting.first

# Test DhanHQ provider (if credentials set)
Providers::DhanhqProvider.new.client rescue "DhanHQ not configured"

# Test Telegram (if credentials set)
TelegramNotifier.send_message("Test message") rescue "Telegram not configured"

# Test config loading
AlgoConfig.fetch('swing_trading.enabled')
```

---

### Step 5: Create Swing-Specific Services

**Priority order:**

1. **Candle Services** (Foundation for everything else)
   - `app/services/candles/daily_ingestor.rb`
   - `app/services/candles/weekly_ingestor.rb`
   - `app/services/candles/intraday_fetcher.rb`

2. **Screener Services** (Find trading opportunities)
   - `app/services/screeners/swing_screener.rb`
   - `app/services/screeners/ai_ranker.rb`
   - `app/services/screeners/final_selector.rb`

3. **Strategy Services** (Execute trades)
   - `app/services/strategies/swing/engine.rb`
   - `app/services/strategies/swing/evaluator.rb`
   - `app/services/strategies/swing/notifier.rb`
   - `app/services/strategies/swing/executor.rb`

---

### Step 6: Create Background Jobs

**Create jobs for:**
- Daily/Weekly candle ingestion
- Swing screener runs
- AI ranking
- Entry/Exit monitoring

**See:** `docs/SWING_LONG_TRADER_MIGRATION_GUIDE.md` for detailed job structure

---

### Step 7: Configure Job Scheduling

**Create `config/recurring.yml`:**
```yaml
candles_daily:
  class: Candles::DailyIngestorJob
  schedule: "0 30 7 * * *"  # 7:30 AM IST daily

candles_weekly:
  class: Candles::WeeklyIngestorJob
  schedule: "0 30 7 * * 1"  # 7:30 AM Monday

swing_screener:
  class: Screeners::SwingScreenerJob
  schedule: "0 40 7 * * 1-5"  # 7:40 AM weekdays
```

---

## ✅ Completed So Far

- [x] Copied all foundation files (models, indicators, providers, services)
- [x] Removed all scalper-specific code
- [x] Created database migrations (instruments, candle_series, settings)
- [x] Ran migrations successfully
- [x] Updated config/algo.yml for swing trading
- [x] Updated config/application.rb (SolidQueue, timezone)
- [x] Added required gems to Gemfile
- [x] Made dhanhq_config.rb conditional (won't fail without gem)

---

## 📝 Quick Reference Commands

```bash
# Install gems
bundle install

# Import instruments
rails instruments:import

# Check import status
rails instruments:status

# Open Rails console
rails console

# Run migrations (if needed)
rails db:migrate

# Check migration status
rails db:migrate:status

# Seed database (verifies key instruments)
rails db:seed
```

---

## 🎯 Success Criteria

Before moving to service creation, verify:
- [ ] `bundle install` completes without errors
- [ ] `rails console` loads without errors
- [ ] `rails instruments:import` successfully imports instruments
- [ ] At least NIFTY, BANKNIFTY instruments are available
- [ ] `AlgoConfig.fetch('swing_trading.enabled')` returns `true`
- [ ] Models can be loaded: `Instrument.first`, `Setting.first`

---

## 📚 Reference Documentation

- **Full Migration Guide**: `docs/SWING_LONG_TRADER_MIGRATION_GUIDE.md`
- **File Mapping**: `docs/SWING_MIGRATION_FILE_MAP.md`
- **Checklist**: `docs/SWING_MIGRATION_CHECKLIST.md`
- **Data Setup**: `docs/SWING_MIGRATION_DATA_SETUP.md`

---

**Last Updated:** After migrations completion

