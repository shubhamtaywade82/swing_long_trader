# frozen_string_literal: true

class CreateAiCalibrations < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_calibrations, if_not_exists: true do |t|
      t.integer :total_outcomes, null: false
      t.datetime :calibrated_at, null: false
      t.json :calibration_data # Stores buckets, win rates, expectancy, recommendations
      t.text :notes

      t.timestamps
    end

    # Index for efficient queries
    unless index_exists?(:ai_calibrations, :calibrated_at)
      add_index :ai_calibrations, :calibrated_at, order: { calibrated_at: :desc }
    end
  end
end
