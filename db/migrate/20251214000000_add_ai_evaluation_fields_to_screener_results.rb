# frozen_string_literal: true

class AddAiEvaluationFieldsToScreenerResults < ActiveRecord::Migration[8.1]
  def change
    add_column :screener_results, :ai_confidence, :decimal, precision: 5, scale: 2, if_not_exists: true
    add_column :screener_results, :ai_risk, :string, if_not_exists: true
    add_column :screener_results, :ai_holding_days, :string, if_not_exists: true
    add_column :screener_results, :ai_comment, :text, if_not_exists: true
    add_column :screener_results, :ai_avoid, :boolean, default: false, if_not_exists: true
    add_column :screener_results, :trade_quality_score, :decimal, precision: 8, scale: 2, if_not_exists: true
    add_column :screener_results, :trade_quality_breakdown, :text, if_not_exists: true # JSON

    # Index for AI confidence queries
    unless index_exists?(:screener_results, :ai_confidence)
      add_index :screener_results, :ai_confidence, order: { ai_confidence: :desc }
    end

    # Index for trade quality score queries
    unless index_exists?(:screener_results, :trade_quality_score)
      add_index :screener_results, :trade_quality_score, order: { trade_quality_score: :desc }
    end
  end
end
