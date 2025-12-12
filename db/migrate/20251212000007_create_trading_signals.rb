# frozen_string_literal: true

class CreateTradingSignals < ActiveRecord::Migration[8.0]
  def change
    create_table :trading_signals, if_not_exists: true do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string :symbol, null: false
      t.string :direction, null: false # long, short
      t.decimal :entry_price, precision: 15, scale: 2, null: false
      t.decimal :stop_loss, precision: 15, scale: 2
      t.decimal :take_profit, precision: 15, scale: 2
      t.integer :quantity, null: false
      t.decimal :order_value, precision: 15, scale: 2, null: false
      t.decimal :confidence, precision: 5, scale: 2 # 0-100
      t.decimal :risk_reward_ratio, precision: 5, scale: 2
      t.integer :holding_days_estimate
      
      # Execution tracking
      t.boolean :executed, default: false, null: false
      t.string :execution_type # paper, live, none
      t.string :execution_status # executed, not_executed, pending_approval
      t.string :execution_reason # why executed or not executed
      t.text :execution_error # error message if execution failed
      
      # Links to executed orders/positions
      t.references :order, foreign_key: true, null: true # Live trading order
      t.references :paper_position, foreign_key: true, null: true # Paper trading position
      
      # Balance information at time of signal
      t.decimal :required_balance, precision: 15, scale: 2
      t.decimal :available_balance, precision: 15, scale: 2
      t.decimal :balance_shortfall, precision: 15, scale: 2
      t.string :balance_type # paper_portfolio, live_account
      
      # Source information
      t.string :source # screener, entry_monitor, manual
      t.string :screener_type # swing, long_term
      
      # Metadata
      t.text :signal_metadata # JSON: full signal details, indicators, etc.
      t.text :execution_metadata # JSON: execution details, risk checks, etc.
      
      t.datetime :signal_generated_at, null: false
      t.datetime :execution_attempted_at
      t.datetime :execution_completed_at

      t.timestamps
    end

    unless index_exists?(:trading_signals, :instrument_id)
      add_index :trading_signals, :instrument_id
    end

    unless index_exists?(:trading_signals, :executed)
      add_index :trading_signals, :executed
    end

    unless index_exists?(:trading_signals, :execution_status)
      add_index :trading_signals, :execution_status
    end

    unless index_exists?(:trading_signals, :execution_type)
      add_index :trading_signals, :execution_type
    end

    unless index_exists?(:trading_signals, [:executed, :signal_generated_at])
      add_index :trading_signals, [:executed, :signal_generated_at]
    end

    unless index_exists?(:trading_signals, [:symbol, :signal_generated_at])
      add_index :trading_signals, [:symbol, :signal_generated_at]
    end
  end
end
