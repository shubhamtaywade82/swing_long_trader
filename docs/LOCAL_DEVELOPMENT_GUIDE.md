# Local Development Guide

**Complete guide to running the Swing + Long-Term Trading System on your local machine**

---

## Prerequisites

### Required Software

1. **Ruby 3.3+**
   ```bash
   # Check version
   ruby -v
   
   # Install via rbenv (recommended)
   rbenv install 3.3.4
   rbenv local 3.3.4
   
   # Or via rvm
   rvm install 3.3.4
   rvm use 3.3.4
   ```

2. **PostgreSQL 15+**
   ```bash
   # Check version
   psql --version
   
   # macOS (Homebrew)
   brew install postgresql@15
   brew services start postgresql@15
   
   # Ubuntu/Debian
   sudo apt-get install postgresql-15
   sudo systemctl start postgresql
   
   # Create PostgreSQL user (if needed)
   createuser -s $USER
   ```

3. **Node.js 18+ and Yarn**
   ```bash
   # Check versions
   node -v
   yarn -v
   
   # Install Node.js (via nvm recommended)
   nvm install 18
   nvm use 18
   
   # Install Yarn
   npm install -g yarn
   ```

4. **Git**
   ```bash
   git --version
   ```

### Optional but Recommended

- **Foreman** (for running multiple processes)
  ```bash
  gem install foreman
  ```

---

## Step-by-Step Setup

### Step 1: Clone Repository

```bash
git clone <repository-url>
cd swing_long_trader
```

### Step 2: Install Dependencies

```bash
# Install Ruby gems
bundle install

# Install Node.js dependencies
yarn install
```

**Troubleshooting:**
- If `bundle install` fails, ensure Ruby version matches `.ruby-version` or `.node-version`
- If PostgreSQL gem fails, install PostgreSQL development headers:
  ```bash
  # macOS
  brew install postgresql@15
  
  # Ubuntu/Debian
  sudo apt-get install libpq-dev
  ```

### Step 3: Configure Environment Variables

Create a `.env` file in the project root:

```bash
# Copy from example if available, or create new
touch .env
```

**Minimum required variables:**

```bash
# .env file
DHANHQ_CLIENT_ID=your_client_id_here
DHANHQ_ACCESS_TOKEN=your_access_token_here
```

**Optional but recommended:**

```bash
# Telegram notifications
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here

# AI ranking (optional)
OPENAI_API_KEY=your_openai_key_here

# Database (if not using defaults)
# DATABASE_URL=postgresql://localhost/swing_long_trader_development

# Rails environment
RAILS_ENV=development

# Logging
RAILS_LOG_LEVEL=debug
```

**Get DhanHQ Credentials:**
1. Sign up at https://dhan.co/
2. Get your `CLIENT_ID` and `ACCESS_TOKEN` from the dashboard

**Get Telegram Bot Token:**
1. Message @BotFather on Telegram
2. Create a new bot with `/newbot`
3. Get the token from BotFather
4. Message your bot to get your chat ID (use @userinfobot)

### Step 4: Setup Database

```bash
# Create databases
rails db:create

# Run migrations
rails db:migrate

# (Optional) Load seed data if available
rails db:seed

# Verify database connection
rails db:version
```

**Troubleshooting:**
- If database creation fails, ensure PostgreSQL is running:
  ```bash
  # Check status
  sudo systemctl status postgresql  # Linux
  brew services list | grep postgresql  # macOS
  
  # Start if needed
  sudo systemctl start postgresql  # Linux
  brew services start postgresql@15  # macOS
  ```

### Step 5: Import Trading Instruments

The system needs instrument master data to operate:

```bash
# Import instruments from DhanHQ API
rails instruments:import

# Check import status
rails instruments:status

# View imported instruments
rails runner "puts Instrument.count"
```

**Note:** This requires valid DhanHQ API credentials and may take a few minutes.

### Step 6: Ingest Historical Candle Data

Historical data is required for indicators and backtesting:

```bash
# Ingest daily candles (last 365 days)
rails candles:daily:ingest

# Or ingest for specific number of days
rails runner "Candles::DailyIngestor.call(days_back: 30)"

# Ingest weekly candles (last 52 weeks)
rails candles:weekly:ingest

# Or ingest for specific number of weeks
rails runner "Candles::WeeklyIngestor.call(weeks_back: 12)"

# Check candle data status
rails candles:status
```

**Note:** This may take 10-30 minutes depending on the number of instruments and days requested.

### Step 7: Verify Setup

```bash
# Run system health checks
rails hardening:check

# Test indicators
rails indicators:test

# View daily metrics
rails metrics:daily
```

---

## Running the Application

### Option 1: Using Foreman (Recommended)

Foreman runs all processes (web server, JavaScript watcher, CSS watcher) together:

```bash
# Start all processes
bin/dev

# Or with Foreman directly
foreman start -f Procfile.dev
```

This starts:
- Rails server on http://localhost:3000
- JavaScript build watcher
- CSS build watcher

### Option 2: Manual Process Management

Run each process in separate terminals:

**Terminal 1 - Rails Server:**
```bash
rails server
# or
rails s
```

**Terminal 2 - JavaScript Watcher:**
```bash
yarn build --watch
```

**Terminal 3 - CSS Watcher:**
```bash
yarn watch:css
```

### Option 3: Rails Server Only (Minimal)

If you don't need live asset compilation:

```bash
# Build assets once
yarn build
yarn build:css

# Start server
rails server
```

---

## Running Background Jobs

The system uses SolidQueue for background job processing.

### Start SolidQueue Worker

**Option 1: Separate Terminal**
```bash
# In a new terminal
bin/rails solid_queue:start
```

**Option 2: Add to Procfile.dev**
Edit `Procfile.dev` to include:
```
web: env RUBY_DEBUG_OPEN=true bin/rails server
js: yarn build --watch
css: yarn watch:css
jobs: bin/rails solid_queue:start
```

Then run:
```bash
bin/dev
```

### Check Job Status

```bash
# View SolidQueue dashboard (if configured)
# Usually at http://localhost:3000/solid_queue

# Or via Rails console
rails console
> SolidQueue::Job.count
> SolidQueue::Job.failed.count
```

### Run Jobs Manually

```bash
# Run a specific job
rails runner "Candles::DailyIngestorJob.perform_now"

# Run screener
rails runner "Screeners::SwingScreenerJob.perform_now"

# Run all scheduled jobs (if configured)
rails runner "SolidQueue::RecurringTask.all.each(&:enqueue)"
```

---

## Common Development Tasks

### Rails Console

```bash
# Start Rails console
rails console
# or
rails c

# Example commands in console:
> Instrument.count
> Instrument.first.symbol_name
> Instrument.first.load_daily_candles(limit: 10)
> CandleSeriesRecord.where(timeframe: '1D').count
```

### Running Tests

```bash
# Run all tests
rails test

# Run specific test file
rails test test/models/instrument_test.rb

# Run tests with coverage
COVERAGE=true rails test
```

### Running Rake Tasks

```bash
# List all available tasks
rails -T

# Run screener
rails screener:swing

# Run backtest
rails backtest:swing[2024-01-01,2024-12-31,100000]

# View metrics
rails metrics:daily

# Check system health
rails hardening:check
```

### Database Tasks

```bash
# Run migrations
rails db:migrate

# Rollback last migration
rails db:rollback

# Check migration status
rails db:migrate:status

# Reset database (WARNING: deletes all data)
rails db:reset

# Create database backup
rails db:dump

# Load database from backup
rails db:load
```

### Asset Compilation

```bash
# Build JavaScript once
yarn build

# Build CSS once
yarn build:css

# Watch JavaScript for changes
yarn build --watch

# Watch CSS for changes
yarn watch:css
```

---

## Development Workflow

### Daily Development

1. **Start your day:**
   ```bash
   # Pull latest changes
   git pull
   
   # Install any new dependencies
   bundle install
   yarn install
   
   # Run migrations if any
   rails db:migrate
   ```

2. **Start development environment:**
   ```bash
   # Start all processes
   bin/dev
   ```

3. **Make changes and test:**
   - Code changes auto-reload (Rails)
   - JavaScript/CSS changes auto-compile (watchers)
   - Test in browser at http://localhost:3000

4. **Run tests:**
   ```bash
   rails test
   ```

### Testing New Features

```bash
# Test screener
rails screener:swing

# Test indicators
rails indicators:test

# Test backtesting
rails backtest:swing[2024-01-01,2024-12-31,100000]

# Test notifications (if Telegram configured)
rails runner "
  Telegram::Notifier.send_daily_candidates(
    candidates: [{symbol: 'RELIANCE', score: 85}],
    timestamp: Time.current
  )
"
```

### Debugging

```bash
# View logs
tail -f log/development.log

# Rails console debugging
rails console
> Instrument.first  # Check data
> Instrument.first.load_daily_candles(limit: 5)  # Test methods

# Add breakpoints (if using debug gem)
# Add: binding.break in your code
# Then run: rails server
```

---

## Environment-Specific Configuration

### Development Environment

Default Rails environment. Uses:
- `config/environments/development.rb`
- Database: `swing_long_trader_development`
- Logging: Verbose, to `log/development.log`
- Asset compilation: On-demand

### Test Environment

```bash
# Run tests
RAILS_ENV=test rails test

# Or Rails sets it automatically for tests
rails test
```

Uses:
- Database: `swing_long_trader_test`
- Logging: Minimal
- Asset compilation: Pre-compiled

### Production-like Local Testing

```bash
# Set production environment
export RAILS_ENV=production

# Precompile assets
rails assets:precompile

# Start server
rails server -e production

# Reset to development
export RAILS_ENV=development
```

---

## Troubleshooting

### Port Already in Use

```bash
# Find process using port 3000
lsof -i :3000  # macOS/Linux
netstat -ano | findstr :3000  # Windows

# Kill process
kill -9 <PID>

# Or use different port
PORT=3001 rails server
```

### Database Connection Errors

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql  # Linux
brew services list | grep postgresql  # macOS

# Check database exists
rails db:version

# Recreate database
rails db:drop db:create db:migrate
```

### Missing Dependencies

```bash
# Reinstall Ruby gems
bundle install

# Reinstall Node packages
yarn install

# Check for system dependencies
# PostgreSQL headers
sudo apt-get install libpq-dev  # Ubuntu/Debian
brew install postgresql@15  # macOS
```

### Asset Compilation Issues

```bash
# Clear asset cache
rails assets:clobber

# Rebuild assets
yarn build
yarn build:css

# Check Node version
node -v  # Should be 18+
```

### API Connection Issues

```bash
# Verify environment variables loaded
rails runner "puts ENV['DHANHQ_CLIENT_ID']"

# Test DhanHQ connection
rails console
> instrument = Instrument.first
> instrument.ltp  # Should return current price

# Check API credentials
# Ensure .env file exists and has correct values
```

### Jobs Not Running

```bash
# Check SolidQueue is running
ps aux | grep solid_queue

# Check for failed jobs
rails console
> SolidQueue::Job.failed.count
> SolidQueue::Job.failed.last&.error_class

# Restart SolidQueue worker
# Stop current process (Ctrl+C) and restart
bin/rails solid_queue:start
```

### Candle Data Issues

```bash
# Check candle counts
rails runner "
  puts 'Daily: ' + CandleSeriesRecord.where(timeframe: '1D').count.to_s
  puts 'Weekly: ' + CandleSeriesRecord.where(timeframe: '1W').count.to_s
"

# Re-ingest for specific instrument
rails runner "
  instrument = Instrument.find_by(symbol_name: 'RELIANCE')
  Candles::DailyIngestor.call(instrument: instrument, days_back: 365)
"

# Clear and re-ingest all
rails runner "
  CandleSeriesRecord.delete_all
  Candles::DailyIngestor.call(days_back: 365)
  Candles::WeeklyIngestor.call(weeks_back: 52)
"
```

---

## Useful Development Commands Reference

### Quick Start (After Initial Setup)

```bash
# Start everything
bin/dev

# In another terminal: Start background jobs
bin/rails solid_queue:start
```

### Common Tasks

```bash
# Run screener
rails screener:swing

# Run backtest
rails backtest:swing[2024-01-01,2024-12-31,100000]

# View metrics
rails metrics:daily

# Check health
rails hardening:check

# Test indicators
rails indicators:test
```

### Database

```bash
# Migrate
rails db:migrate

# Rollback
rails db:rollback

# Reset (WARNING: deletes data)
rails db:reset

# Console
rails console
```

### Testing

```bash
# All tests
rails test

# Specific test
rails test test/models/instrument_test.rb

# With coverage
COVERAGE=true rails test
```

### Logs

```bash
# View logs
tail -f log/development.log

# Clear logs
> log/development.log
```

---

## Next Steps

1. **Explore the Codebase:**
   - Check `app/models/` for data models
   - Check `app/services/` for business logic
   - Check `app/jobs/` for background jobs
   - Check `config/` for configuration

2. **Read Documentation:**
   - [Getting Started](GETTING_STARTED.md) - Detailed setup guide
   - [System Overview](SYSTEM_OVERVIEW.md) - System architecture
   - [Architecture](architecture.md) - Technical details
   - [Runbook](runbook.md) - Operational procedures

3. **Run Examples:**
   - Try running screeners
   - Run backtests
   - Test indicators
   - Explore Rails console

---

## Tips for Productive Development

1. **Use Rails Console:** Great for quick testing and data inspection
2. **Watch Logs:** Keep `tail -f log/development.log` running
3. **Use Foreman:** `bin/dev` manages all processes automatically
4. **Test Frequently:** Run `rails test` often during development
5. **Use Git:** Commit often, use meaningful commit messages
6. **Read Error Messages:** Rails provides helpful error messages and stack traces

---

**Happy Coding!** 🚀
