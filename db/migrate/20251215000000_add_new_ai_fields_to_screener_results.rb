# frozen_string_literal: true

class AddNewAIFieldsToScreenerResults < ActiveRecord::Migration[8.1]
  def change
    add_column :screener_results, :ai_stage, :string, if_not_exists: true
    add_column :screener_results, :ai_momentum_trend, :string, if_not_exists: true
    add_column :screener_results, :ai_price_position, :string, if_not_exists: true
    add_column :screener_results, :ai_entry_timing, :string, if_not_exists: true
    add_column :screener_results, :ai_continuation_bias, :string, if_not_exists: true
    add_column :screener_results, :ai_primary_risk, :text, if_not_exists: true
    add_column :screener_results, :ai_invalidate_if, :text, if_not_exists: true
  end
end
