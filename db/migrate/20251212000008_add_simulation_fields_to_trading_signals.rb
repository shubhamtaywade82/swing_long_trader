# frozen_string_literal: true

class AddSimulationFieldsToTradingSignals < ActiveRecord::Migration[8.0]
  def change
    add_column :trading_signals, :simulated, :boolean, default: false, null: false
    add_column :trading_signals, :simulated_at, :datetime
    add_column :trading_signals, :simulated_exit_price, :decimal, precision: 15, scale: 2
    add_column :trading_signals, :simulated_exit_date, :datetime
    add_column :trading_signals, :simulated_exit_reason, :string # sl_hit, tp_hit, manual, time_based
    add_column :trading_signals, :simulated_pnl, :decimal, precision: 15, scale: 2
    add_column :trading_signals, :simulated_pnl_pct, :decimal, precision: 8, scale: 2
    add_column :trading_signals, :simulated_holding_days, :integer
    add_column :trading_signals, :simulation_metadata, :text # JSON: simulation details, exit conditions, etc.

    unless index_exists?(:trading_signals, :simulated)
      add_index :trading_signals, :simulated
    end

    unless index_exists?(:trading_signals, [:executed, :simulated])
      add_index :trading_signals, [:executed, :simulated]
    end
  end
end
