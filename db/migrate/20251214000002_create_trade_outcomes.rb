# frozen_string_literal: true

class CreateTradeOutcomes < ActiveRecord::Migration[8.1]
  def change
    create_table :trade_outcomes, if_not_exists: true do |t|
      t.references :screener_run, null: false, foreign_key: true
      t.references :instrument, null: false, foreign_key: true
      t.string :symbol, null: false
      t.string :trading_mode, null: false # paper, live
      
      # Entry details
      t.decimal :entry_price, precision: 15, scale: 4, null: false
      t.datetime :entry_time, null: false
      t.integer :quantity, null: false
      
      # Risk management
      t.decimal :stop_loss, precision: 15, scale: 4
      t.decimal :take_profit, precision: 15, scale: 4
      t.decimal :risk_per_share, precision: 15, scale: 4
      t.decimal :risk_amount, precision: 15, scale: 4
      
      # Exit details
      t.decimal :exit_price, precision: 15, scale: 4
      t.datetime :exit_time
      t.string :exit_reason # target_hit, stop_hit, manual, time_based, signal_invalidated
      
      # Performance metrics
      t.decimal :pnl, precision: 15, scale: 4
      t.decimal :pnl_percent, precision: 8, scale: 2
      t.decimal :r_multiple, precision: 8, scale: 2 # PnL / Risk
      t.integer :holding_days
      
      # Attribution
      t.decimal :screener_score, precision: 8, scale: 2
      t.decimal :trade_quality_score, precision: 8, scale: 2
      t.decimal :ai_confidence, precision: 5, scale: 2
      t.string :tier # tier_1, tier_2, tier_3
      t.string :stage # final (from FinalSelector)
      
      # Status
      t.string :status, default: "open" # open, closed, cancelled
      t.text :notes # Additional context
      
      # Link to actual position (if exists)
      t.integer :position_id # Links to SwingPosition or PaperPosition
      t.string :position_type # swing_position, paper_position

      t.timestamps
    end

    # Indexes for efficient queries
    unless index_exists?(:trade_outcomes, [:screener_run_id, :status])
      add_index :trade_outcomes, [:screener_run_id, :status]
    end

    unless index_exists?(:trade_outcomes, [:instrument_id, :status])
      add_index :trade_outcomes, [:instrument_id, :status]
    end

    unless index_exists?(:trade_outcomes, [:trading_mode, :status])
      add_index :trade_outcomes, [:trading_mode, :status]
    end

    unless index_exists?(:trade_outcomes, [:entry_time])
      add_index :trade_outcomes, :entry_time, order: { entry_time: :desc }
    end

    unless index_exists?(:trade_outcomes, [:exit_time])
      add_index :trade_outcomes, :exit_time, order: { exit_time: :desc }
    end

    # Index for AI confidence analysis
    unless index_exists?(:trade_outcomes, :ai_confidence)
      add_index :trade_outcomes, :ai_confidence, order: { ai_confidence: :desc }
    end

    # Index for R-multiple analysis
    unless index_exists?(:trade_outcomes, :r_multiple)
      add_index :trade_outcomes, :r_multiple, order: { r_multiple: :desc }
    end
  end
end
