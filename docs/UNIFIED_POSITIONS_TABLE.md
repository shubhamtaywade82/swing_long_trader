# Unified Positions Table Architecture

## Overview

The system uses a **single `positions` table** for both live and paper trading positions, with a `trading_mode` flag to distinguish between them. Portfolio snapshots use **Single Table Inheritance (STI)** from the same table.

## Architecture

### Single Table for All Positions

```
positions table
├── type: nil/'Position' (regular positions) or 'Portfolio' (portfolio snapshots)
├── trading_mode: 'live' | 'paper' (for regular positions)
├── portfolio_date: Date (links positions to portfolio snapshots)
├── portfolio_type: 'live' | 'paper' (for Portfolio type records)
└── ... (all position fields)
```

### Key Benefits

1. **Unified Data Model**: Single source of truth for all positions
2. **Simplified Queries**: One table to query for both live and paper positions
3. **Portfolio STI**: Portfolio snapshots inherit from Position table
4. **Position Continuation**: Easy to track positions that continue from previous day
5. **Consistent Schema**: Same fields and structure for all positions

## Database Schema

### Positions Table

```ruby
create_table :positions do |t|
  # STI
  t.string :type  # nil/'Position' or 'Portfolio'
  
  # Trading mode
  t.string :trading_mode, default: 'live'  # 'live' | 'paper'
  
  # Portfolio snapshot linking
  t.date :portfolio_date
  t.string :portfolio_type  # For Portfolio type records
  
  # Position details (for regular positions)
  t.references :instrument
  t.references :order
  t.references :exit_order
  t.references :trading_signal
  t.references :paper_portfolio  # For backward compatibility
  
  t.string :symbol
  t.string :direction  # 'long' | 'short'
  t.decimal :entry_price
  t.decimal :current_price
  t.integer :quantity
  t.string :status  # 'open' | 'closed' | 'partially_closed'
  
  # Exit levels
  t.decimal :stop_loss
  t.decimal :take_profit
  
  # P&L tracking
  t.decimal :unrealized_pnl
  t.decimal :realized_pnl
  
  # Continuation tracking
  t.boolean :continued_from_previous_day, default: false
  
  # Portfolio aggregation fields (for Portfolio type)
  t.decimal :opening_capital
  t.decimal :closing_capital
  t.decimal :total_equity
  t.integer :open_positions_count
  t.integer :closed_positions_count
  
  t.timestamps
end
```

## Model Structure

### Position Model

```ruby
class Position < ApplicationRecord
  # Scopes
  scope :live, -> { where(trading_mode: 'live').or(where(trading_mode: nil)) }
  scope :paper, -> { where(trading_mode: 'paper') }
  scope :regular_positions, -> { where(type: [nil, 'Position']) }
  
  # Methods
  def live?
    trading_mode.nil? || trading_mode == 'live'
  end
  
  def paper?
    trading_mode == 'paper'
  end
end
```

### Portfolio Model (STI)

```ruby
class Portfolio < Position
  self.table_name = "positions"
  
  # Portfolio-specific scopes
  scope :live, -> { where(portfolio_type: 'live') }
  scope :paper, -> { where(portfolio_type: 'paper') }
  
  # Get positions for this portfolio snapshot
  def positions
    Position.regular_positions
            .where(trading_mode: portfolio_type)
            .where(portfolio_date: portfolio_date)
  end
  
  # Get continued positions
  def continued_positions
    positions.where(continued_from_previous_day: true)
  end
end
```

## Usage Examples

### Creating Positions

**Live Position:**
```ruby
Position.create!(
  trading_mode: 'live',
  instrument: instrument,
  symbol: 'RELIANCE',
  direction: 'long',
  entry_price: 2500,
  current_price: 2500,
  quantity: 10,
  status: 'open',
  opened_at: Time.current
)
```

**Paper Position:**
```ruby
Position.create!(
  trading_mode: 'paper',
  paper_portfolio: portfolio,  # For backward compatibility
  instrument: instrument,
  symbol: 'RELIANCE',
  direction: 'long',
  entry_price: 2500,
  current_price: 2500,
  quantity: 10,
  status: 'open',
  opened_at: Time.current
)
```

### Querying Positions

```ruby
# All live positions
live_positions = Position.live.open

# All paper positions
paper_positions = Position.paper.open

# Positions for a specific date
positions_today = Position.where(portfolio_date: Date.today)

# Continued positions
continued = Position.where(continued_from_previous_day: true)
```

### Creating Portfolio Snapshots

```ruby
# Create portfolio snapshot
portfolio = Portfolio.create_from_positions(
  date: Date.today,
  portfolio_type: 'live'  # or 'paper'
)

# Get positions in portfolio
all_positions = portfolio.positions
continued = portfolio.continued_positions
new_today = portfolio.new_positions
closed_today = portfolio.closed_positions_today
```

## Migration from PaperPosition

A migration script (`20251212000011_migrate_paper_positions_to_positions.rb`) migrates existing `PaperPosition` records to the unified `positions` table:

```bash
rails db:migrate
```

The migration:
1. Copies all `PaperPosition` records to `positions` table
2. Sets `trading_mode = 'paper'`
3. Maps fields (e.g., `sl` → `stop_loss`, `tp` → `take_profit`)
4. Calculates P&L fields based on status
5. Preserves `paper_portfolio_id` for backward compatibility

## Backward Compatibility

During migration, the system maintains backward compatibility:

1. **PaperPosition Model**: Can be kept as a delegator/wrapper if needed
2. **paper_portfolio_id**: Preserved in positions table
3. **Services**: Updated to create positions in unified table

## Portfolio Snapshot Flow

1. **End of Trading Day**: `Portfolios::DailySnapshotJob` runs at 4:00 PM IST
2. **Get Positions**: Queries positions by `trading_mode` and date
3. **Mark Continued**: Identifies positions that continue from previous day
4. **Calculate Metrics**: Computes capital, equity, P&L, exposure, etc.
5. **Create Portfolio**: Creates Portfolio record (STI) with aggregated data
6. **Link Positions**: Updates positions with `portfolio_date` and ensures `trading_mode` is set

## Key Features

### Position Continuation

Positions that continue from previous trading day are automatically identified:

```ruby
# When creating portfolio snapshot
previous_portfolio = Portfolio.find_by(portfolio_type: 'live', portfolio_date: Date.yesterday)
previous_open = previous_portfolio.open_positions_at_eod

# Mark matching positions as continued
current_open.each do |pos|
  if previous_open.any? { |p| p.symbol == pos.symbol && p.direction == pos.direction }
    pos.update_column(:continued_from_previous_day, true)
  end
end
```

### Unified Queries

```ruby
# Get all open positions (live + paper)
all_open = Position.open

# Get all positions for a date
positions_for_date = Position.where(portfolio_date: Date.today)

# Get portfolio metrics
live_portfolio = Portfolio.live.by_date(Date.today).first
paper_portfolio = Portfolio.paper.by_date(Date.today).first
```

## Benefits

1. **Single Source of Truth**: All positions in one table
2. **Simplified Queries**: No need to join multiple tables
3. **Portfolio STI**: Portfolio snapshots use same table structure
4. **Position Tracking**: Easy to track continuation across days
5. **Consistent Schema**: Same fields for live and paper positions
6. **Better Performance**: Single table queries are faster than joins

## Migration Checklist

- [x] Add `trading_mode` column to positions table
- [x] Add `portfolio_date` and portfolio fields
- [x] Update Position model with scopes and methods
- [x] Update Portfolio model to use unified table
- [x] Update paper trading services to create Position records
- [x] Update live trading executor to set `trading_mode='live'`
- [x] Create migration script for PaperPosition → Position
- [x] Update rake tasks to use unified table
- [x] Update documentation

## Notes

- `PaperPosition` table can be deprecated after migration
- `paper_portfolio_id` is kept for backward compatibility
- Portfolio snapshots are created daily at end of trading day
- Positions are linked to portfolio snapshots via `portfolio_date`
