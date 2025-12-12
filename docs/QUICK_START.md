# Quick Start Guide

**Get up and running in 5 minutes**

---

## First Time Setup

```bash
# 1. Install dependencies
bundle install
yarn install

# 2. Setup database
rails db:create db:migrate

# 3. Configure environment (create .env file)
# Add: DHANHQ_CLIENT_ID and DHANHQ_ACCESS_TOKEN

# 4. Import instruments
rails instruments:import

# 5. Ingest candle data (optional, but recommended)
rails candles:daily:ingest
```

---

## Daily Development

```bash
# Start everything (web server + asset watchers)
bin/dev

# In another terminal: Start background jobs
bin/rails solid_queue:start
```

**Access:**
- Web app: http://localhost:3000
- Logs: `tail -f log/development.log`
- Console: `rails console`

---

## Common Commands

```bash
# Run screener
rails screener:swing

# Run backtest
rails backtest:swing[2024-01-01,2024-12-31,100000]

# View metrics
rails metrics:daily

# Check health
rails hardening:check

# Run tests
rails test

# Rails console
rails console
```

---

## Troubleshooting

```bash
# Database issues?
rails db:version  # Check connection
sudo systemctl status postgresql  # Check PostgreSQL running

# Port in use?
lsof -i :3000  # Find process
kill -9 <PID>  # Kill it

# Missing dependencies?
bundle install  # Ruby gems
yarn install    # Node packages
```

---

## Full Documentation

- **[Local Development Guide](LOCAL_DEVELOPMENT_GUIDE.md)** - Complete local setup
- **[Deployment Guide](KAMAL_DEPLOYMENT_GUIDE.md)** - Deploy to production
- **[Getting Started](GETTING_STARTED.md)** - Detailed setup
- **[System Overview](SYSTEM_OVERVIEW.md)** - Architecture & features

---

**Need help?** Check the [Local Development Guide](LOCAL_DEVELOPMENT_GUIDE.md) for detailed instructions.
