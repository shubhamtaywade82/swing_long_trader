# frozen_string_literal: true

class CreateScreenerResults < ActiveRecord::Migration[8.1]
  def change
    create_table :screener_results, if_not_exists: true do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string :screener_type, null: false # swing, longterm
      t.string :symbol, null: false
      t.decimal :score, precision: 8, scale: 2, null: false
      t.decimal :base_score, precision: 8, scale: 2, default: 0
      t.decimal :mtf_score, precision: 8, scale: 2, default: 0
      t.text :indicators # JSON: technical indicators
      t.text :metadata # JSON: additional metadata
      t.text :multi_timeframe # JSON: multi-timeframe analysis
      t.datetime :analyzed_at, null: false

      t.timestamps
    end

    # Indexes for efficient queries
    unless index_exists?(:screener_results, [:screener_type, :analyzed_at])
      add_index :screener_results, [:screener_type, :analyzed_at], order: { analyzed_at: :desc }
    end

    unless index_exists?(:screener_results, [:screener_type, :score])
      add_index :screener_results, [:screener_type, :score], order: { score: :desc }
    end

    unless index_exists?(:screener_results, [:symbol, :screener_type, :analyzed_at])
      add_index :screener_results, [:symbol, :screener_type, :analyzed_at], 
                 name: "index_screener_results_on_symbol_type_analyzed"
    end

    unless index_exists?(:screener_results, :instrument_id)
      add_index :screener_results, :instrument_id
    end
  end
end
