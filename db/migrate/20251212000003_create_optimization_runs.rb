# frozen_string_literal: true

class CreateOptimizationRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :optimization_runs, if_not_exists: true do |t|
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :strategy_type, null: false # 'swing' or 'long_term'
      t.decimal :initial_capital, precision: 15, scale: 2, null: false, default: 100000
      t.string :optimization_metric, null: false, default: 'sharpe_ratio' # sharpe_ratio, total_return, etc.
      t.boolean :use_walk_forward, default: true
      t.integer :total_combinations_tested, default: 0
      t.text :parameter_ranges # JSON: parameter ranges tested
      t.text :best_parameters # JSON: best parameter combination
      t.text :best_metrics # JSON: metrics for best parameters
      t.text :all_results # JSON: all parameter combinations and their results
      t.text :sensitivity_analysis # JSON: parameter sensitivity analysis
      t.string :status, default: 'pending' # pending, running, completed, failed
      t.text :error_message

      t.timestamps
    end

    unless index_exists?(:optimization_runs, :strategy_type)
      add_index :optimization_runs, :strategy_type
    end

    unless index_exists?(:optimization_runs, :status)
      add_index :optimization_runs, :status
    end

    unless index_exists?(:optimization_runs, [:start_date, :end_date])
      add_index :optimization_runs, [:start_date, :end_date]
    end

    unless index_exists?(:optimization_runs, :created_at)
      add_index :optimization_runs, :created_at
    end
  end
end
