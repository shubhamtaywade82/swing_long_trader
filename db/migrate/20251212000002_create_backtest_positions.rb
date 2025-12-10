# frozen_string_literal: true

class CreateBacktestPositions < ActiveRecord::Migration[8.0]
  def change
    create_table :backtest_positions, if_not_exists: true do |t|
      t.references :backtest_run, null: false, foreign_key: true
      t.references :instrument, null: false, foreign_key: true
      t.datetime :entry_date, null: false
      t.datetime :exit_date
      t.string :direction, null: false # 'long' or 'short'
      t.decimal :entry_price, precision: 15, scale: 5, null: false
      t.decimal :exit_price, precision: 15, scale: 5
      t.integer :quantity, null: false
      t.decimal :stop_loss, precision: 15, scale: 5
      t.decimal :take_profit, precision: 15, scale: 5
      t.decimal :pnl, precision: 15, scale: 2
      t.decimal :pnl_pct, precision: 10, scale: 4
      t.integer :holding_days
      t.string :exit_reason # 'stop_loss', 'take_profit', 'trailing_stop', 'time_limit', etc.

      t.timestamps
    end

    unless index_exists?(:backtest_positions, :backtest_run_id)
      add_index :backtest_positions, :backtest_run_id
    end

    unless index_exists?(:backtest_positions, :instrument_id)
      add_index :backtest_positions, :instrument_id
    end

    unless index_exists?(:backtest_positions, [:entry_date, :exit_date])
      add_index :backtest_positions, [:entry_date, :exit_date]
    end
  end
end

