# frozen_string_literal: true

class CreateScreenerRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :screener_runs, if_not_exists: true do |t|
      t.string :screener_type, null: false # swing, longterm
      t.integer :universe_size, null: false
      t.string :market_regime # trending, ranging, volatile
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.string :status, default: "running" # running, completed, failed
      t.text :error_message
      t.json :metrics # eligible_count, ranked_count, ai_evaluated_count, final_count, etc.
      t.decimal :ai_cost, precision: 10, scale: 4, default: 0
      t.integer :ai_calls_count, default: 0

      t.timestamps
    end

    # Indexes
    unless index_exists?(:screener_runs, [:screener_type, :started_at])
      add_index :screener_runs, [:screener_type, :started_at], order: { started_at: :desc }
    end

    unless index_exists?(:screener_runs, :status)
      add_index :screener_runs, :status
    end

    # Add screener_run_id to screener_results
    unless column_exists?(:screener_results, :screener_run_id)
      add_reference :screener_results, :screener_run, foreign_key: true, index: true
    end

    # Add stage tracking to screener_results
    unless column_exists?(:screener_results, :stage)
      add_column :screener_results, :stage, :string # screener, ranked, ai_evaluated, final
    end

    # Add idempotency for AI evaluations
    unless column_exists?(:screener_results, :ai_eval_id)
      add_column :screener_results, :ai_eval_id, :string
      add_index :screener_results, :ai_eval_id, unique: true, if_not_exists: true
    end

    # Add AI status tracking
    unless column_exists?(:screener_results, :ai_status)
      add_column :screener_results, :ai_status, :string # pending, evaluated, failed, skipped
    end
  end
end
