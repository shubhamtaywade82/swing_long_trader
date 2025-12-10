# frozen_string_literal: true

class CreateBacktestRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :backtest_runs, if_not_exists: true do |t|
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :strategy_type, null: false # 'swing' or 'long_term'
      t.decimal :initial_capital, precision: 15, scale: 2, null: false, default: 100000
      t.decimal :risk_per_trade, precision: 5, scale: 2, null: false, default: 2.0
      t.decimal :total_return, precision: 10, scale: 2
      t.decimal :annualized_return, precision: 10, scale: 2
      t.decimal :max_drawdown, precision: 10, scale: 2
      t.decimal :sharpe_ratio, precision: 10, scale: 4
      t.decimal :win_rate, precision: 5, scale: 2
      t.integer :total_trades, default: 0
      t.string :status, default: 'pending' # pending, running, completed, failed
      t.text :config # JSON config used for backtest
      t.text :results # JSON results summary

      t.timestamps
    end

    unless index_exists?(:backtest_runs, :strategy_type)
      add_index :backtest_runs, :strategy_type
    end

    unless index_exists?(:backtest_runs, :status)
      add_index :backtest_runs, :status
    end

    unless index_exists?(:backtest_runs, [:start_date, :end_date])
      add_index :backtest_runs, [:start_date, :end_date]
    end
  end
end

