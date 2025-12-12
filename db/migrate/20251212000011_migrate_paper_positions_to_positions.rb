# frozen_string_literal: true

# Migration script to migrate PaperPosition records to unified Position table
class MigratePaperPositionsToPositions < ActiveRecord::Migration[8.0]
  def up
    # Check if paper_positions table exists
    return unless table_exists?(:paper_positions)

    # Migrate each PaperPosition to Position
    execute <<-SQL
      INSERT INTO positions (
        paper_portfolio_id,
        instrument_id,
        trading_mode,
        symbol,
        direction,
        entry_price,
        current_price,
        quantity,
        stop_loss,
        take_profit,
        status,
        opened_at,
        closed_at,
        exit_price,
        exit_reason,
        unrealized_pnl,
        unrealized_pnl_pct,
        realized_pnl,
        realized_pnl_pct,
        holding_days,
        metadata,
        created_at,
        updated_at
      )
      SELECT 
        paper_portfolio_id,
        instrument_id,
        'paper' as trading_mode,
        (SELECT symbol_name FROM instruments WHERE id = paper_positions.instrument_id) as symbol,
        direction,
        entry_price,
        current_price,
        quantity,
        sl as stop_loss,
        tp as take_profit,
        status,
        opened_at,
        closed_at,
        exit_price,
        exit_reason,
        CASE 
          WHEN status = 'open' THEN pnl
          ELSE 0
        END as unrealized_pnl,
        CASE 
          WHEN status = 'open' THEN pnl_pct
          ELSE 0
        END as unrealized_pnl_pct,
        CASE 
          WHEN status = 'closed' THEN pnl
          ELSE 0
        END as realized_pnl,
        CASE 
          WHEN status = 'closed' THEN pnl_pct
          ELSE 0
        END as realized_pnl_pct,
        CASE 
          WHEN closed_at IS NOT NULL THEN EXTRACT(DAY FROM (closed_at - opened_at))
          ELSE EXTRACT(DAY FROM (NOW() - opened_at))
        END as holding_days,
        metadata,
        created_at,
        updated_at
      FROM paper_positions
      WHERE NOT EXISTS (
        SELECT 1 FROM positions 
        WHERE positions.paper_portfolio_id = paper_positions.paper_portfolio_id
        AND positions.instrument_id = paper_positions.instrument_id
        AND positions.trading_mode = 'paper'
        AND positions.opened_at = paper_positions.opened_at
      );
    SQL

    Rails.logger.info("[Migration] Migrated #{PaperPosition.count} paper positions to unified positions table")
  end

  def down
    # Remove migrated paper positions
    execute <<-SQL
      DELETE FROM positions WHERE trading_mode = 'paper';
    SQL
  end
end
