# frozen_string_literal: true

class CreatePositions < ActiveRecord::Migration[8.0]
  def change
    create_table :positions, if_not_exists: true do |t|
      t.references :instrument, null: false, foreign_key: true
      t.references :order, foreign_key: true # Entry order
      t.references :exit_order, foreign_key: { to_table: :orders }, null: true # Exit order
      t.references :trading_signal, foreign_key: true, null: true # Link to signal
      
      # Position details
      t.string :symbol, null: false
      t.string :direction, null: false # long, short
      t.decimal :entry_price, precision: 15, scale: 2, null: false
      t.decimal :current_price, precision: 15, scale: 2, null: false
      t.integer :quantity, null: false
      t.decimal :average_entry_price, precision: 15, scale: 2 # If multiple entries
      t.decimal :filled_quantity, precision: 15, scale: 2, default: 0
      
      # Exit levels
      t.decimal :stop_loss, precision: 15, scale: 2
      t.decimal :take_profit, precision: 15, scale: 2
      t.decimal :trailing_stop_distance, precision: 15, scale: 2
      t.decimal :trailing_stop_pct, precision: 8, scale: 2
      t.decimal :highest_price, precision: 15, scale: 2 # For trailing stop
      t.decimal :lowest_price, precision: 15, scale: 2 # For trailing stop
      
      # Status and tracking
      t.string :status, default: "open", null: false # open, closed, partially_closed
      t.datetime :opened_at, null: false
      t.datetime :closed_at
      t.decimal :exit_price, precision: 15, scale: 2
      t.string :exit_reason # sl_hit, tp_hit, trailing_stop, manual, time_based, signal_exit
      
      # P&L tracking
      t.decimal :unrealized_pnl, precision: 15, scale: 2, default: 0
      t.decimal :unrealized_pnl_pct, precision: 8, scale: 2, default: 0
      t.decimal :realized_pnl, precision: 15, scale: 2, default: 0
      t.decimal :realized_pnl_pct, precision: 8, scale: 2, default: 0
      t.integer :holding_days, default: 0
      
      # DhanHQ sync
      t.string :dhan_position_id # DhanHQ position ID if available
      t.datetime :last_synced_at # Last sync with DhanHQ
      t.text :dhan_position_data # JSON data from DhanHQ
      t.boolean :synced_with_dhan, default: false
      
      # Metadata
      t.text :metadata # JSON: signal info, risk checks, etc.
      t.text :sync_metadata # JSON: sync history, changes, etc.

      t.timestamps
    end

    unless index_exists?(:positions, :instrument_id)
      add_index :positions, :instrument_id
    end

    unless index_exists?(:positions, :status)
      add_index :positions, :status
    end

    unless index_exists?(:positions, :order_id)
      add_index :positions, :order_id
    end

    unless index_exists?(:positions, :trading_signal_id)
      add_index :positions, :trading_signal_id
    end

    unless index_exists?(:positions, [:status, :opened_at])
      add_index :positions, [:status, :opened_at]
    end

    unless index_exists?(:positions, :dhan_position_id)
      add_index :positions, :dhan_position_id
    end

    unless index_exists?(:positions, :synced_with_dhan)
      add_index :positions, :synced_with_dhan
    end
  end
end
