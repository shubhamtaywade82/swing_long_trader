# Portfolio Single Table Inheritance (STI) Guide

## Overview

Portfolio uses **Single Table Inheritance (STI)** from the `Position` table. This means:
- Portfolio records are stored in the `positions` table with `type = 'Portfolio'`
- Portfolio aggregates positions that continue from the previous trading day
- Portfolio includes both live and paper positions (paper positions are tracked via metadata)

## Architecture

### Database Structure

Portfolio extends the `positions` table with additional fields:

```ruby
# STI type column
type: 'Portfolio'  # vs nil/'Position' for regular positions

# Portfolio snapshot date
portfolio_date: Date  # Date of portfolio snapshot

# Portfolio type
portfolio_type: 'live' | 'paper'

# Portfolio aggregation fields
opening_capital: Decimal
closing_capital: Decimal
total_equity: Decimal
available_capital: Decimal
total_exposure: Decimal
open_positions_count: Integer
closed_positions_count: Integer
utilization_pct: Decimal
win_rate: Decimal
peak_equity: Decimal

# Position continuation tracking
continued_from_previous_day: Boolean  # For live positions
```

### Model Structure

```ruby
class Position < ApplicationRecord
  # Regular positions
end

class Portfolio < Position
  # Portfolio snapshots (STI)
  # Uses same table: positions
end
```

## Key Features

### 1. Positions That Continue From Previous Day

Portfolio automatically identifies and tracks positions that continue from the previous trading day:

```ruby
portfolio = Portfolio.find_by(portfolio_type: 'live', portfolio_date: Date.today)

# Get positions that continued from yesterday
continued = portfolio.continued_positions

# Get new positions opened today
new_today = portfolio.new_positions

# Get positions closed today
closed_today = portfolio.closed_positions_today
```

### 2. Daily Portfolio Snapshots

Portfolio snapshots are created at end of trading day:

```ruby
# Create snapshot for today
Portfolio.create_from_positions(
  date: Date.today,
  portfolio_type: 'live'
)

# Or use the service
Portfolios::DailySnapshot.create_for_date(
  date: Date.today,
  portfolio_type: 'all'  # or 'live' or 'paper'
)
```

### 3. Position Aggregation

Portfolio aggregates all positions for a given date:

```ruby
portfolio = Portfolio.find_by(portfolio_type: 'live', portfolio_date: Date.today)

# Get all positions in this portfolio
all_positions = portfolio.positions

# Get open positions at end of day
open_eod = portfolio.open_positions_at_eod
```

## Usage

### Creating Daily Snapshots

**Automatically (via recurring job):**
```yaml
# config/recurring.yml
daily_portfolio_snapshot:
  class: Portfolios::DailySnapshotJob
  schedule: "0 16 * * 1-5"  # 4:00 PM IST (after market close)
```

**Manually:**
```bash
# Create snapshot for today
rails portfolios:snapshot

# Create snapshot for specific date
rails portfolios:snapshot_date[2024-12-12]
```

### Querying Portfolios

```ruby
# Get today's live portfolio
live_portfolio = Portfolio.live.by_date(Date.today).first

# Get recent portfolios
recent = Portfolio.live.recent.limit(10)

# Get portfolio metrics
live_portfolio.total_equity
live_portfolio.realized_pnl
live_portfolio.unrealized_pnl
live_portfolio.open_positions_count
live_portfolio.closed_positions_count
```

### Viewing Portfolio Details

```bash
# Show today's portfolio
rails portfolios:show

# Show portfolio for specific date
rails portfolios:show_date[2024-12-12]

# List all portfolios
rails portfolios:list
```

## Position Continuation Logic

### For Live Positions

1. When creating a portfolio snapshot, the system:
   - Checks for previous day's portfolio
   - Compares open positions from previous day with current open positions
   - Marks matching positions with `continued_from_previous_day = true`
   - Updates positions with `portfolio_date` and `portfolio_type`

2. Positions that match (same symbol + direction) are marked as continued

### For Paper Positions

Since `PaperPosition` is in a separate table:
- Continuation info is stored in `metadata` JSON field
- `metadata['continued_from_previous_day'] = true`
- `metadata['portfolio_date']` stores the snapshot date

## Portfolio Metrics

Portfolio calculates:

- **Opening Capital**: Previous day's closing capital (or initial capital)
- **Closing Capital**: Opening capital + realized P&L
- **Total Equity**: Closing capital + unrealized P&L
- **Realized P&L**: Sum of P&L from positions closed today
- **Unrealized P&L**: Sum of P&L from open positions
- **Total Exposure**: Sum of (current_price × quantity) for open positions
- **Utilization %**: (Total Exposure / Total Equity) × 100
- **Win Rate**: % of closed positions with positive P&L
- **Open Positions Count**: Number of open positions at EOD
- **Closed Positions Count**: Number of positions closed today

## Example Workflow

```ruby
# Day 1: Create initial portfolio
portfolio_day1 = Portfolio.create_from_positions(
  date: Date.today,
  portfolio_type: 'live'
)
# Opening Capital: ₹100,000
# Open Positions: 5
# Total Equity: ₹105,000

# Day 2: Create next day's portfolio
portfolio_day2 = Portfolio.create_from_positions(
  date: Date.today + 1.day,
  portfolio_type: 'live'
)
# Opening Capital: ₹105,000 (from Day 1 closing)
# Continued Positions: 3 (from Day 1)
# New Positions: 2 (opened today)
# Closed Positions: 2 (closed today)
# Total Equity: ₹108,000
```

## Rake Tasks

```bash
# Create snapshot for today
rails portfolios:snapshot

# Create snapshot for specific date
rails portfolios:snapshot_date[2024-12-12]

# Show today's portfolio
rails portfolios:show

# Show portfolio for specific date
rails portfolios:show_date[2024-12-12]

# List all portfolios
rails portfolios:list
```

## Migration

Run the migration to add STI support:

```bash
rails db:migrate
```

This adds:
- `type` column for STI
- `portfolio_date` column for snapshot dates
- `portfolio_type` column (live/paper)
- Portfolio aggregation fields
- `continued_from_previous_day` flag

## Notes

1. **STI Benefits**: Portfolio shares the same table as Position, making queries efficient and maintaining referential integrity

2. **Position Tracking**: All positions are linked to their portfolio snapshot via `portfolio_date` and `portfolio_type`

3. **Continuation Logic**: Positions that continue from previous day are automatically identified and marked

4. **Paper Positions**: Paper positions are tracked separately but aggregated into Portfolio snapshots via metadata

5. **Daily Snapshots**: Snapshots are created at end of trading day (4:00 PM IST) via recurring job
