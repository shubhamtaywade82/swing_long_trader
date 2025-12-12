# frozen_string_literal: true

class OptimizationRun < ApplicationRecord
  validates :start_date, :end_date, :strategy_type, :initial_capital, :optimization_metric, presence: true
  validates :strategy_type, inclusion: { in: %w[swing long_term] }
  validates :status, inclusion: { in: %w[pending running completed failed] }
  validates :optimization_metric, inclusion: { in: %w[sharpe_ratio sortino_ratio total_return annualized_return profit_factor win_rate composite] }

  scope :completed, -> { where(status: 'completed') }
  scope :swing, -> { where(strategy_type: 'swing') }
  scope :long_term, -> { where(strategy_type: 'long_term') }
  scope :recent, -> { order(created_at: :desc) }

  def parameter_ranges_hash
    return {} if parameter_ranges.blank?

    JSON.parse(parameter_ranges)
  rescue JSON::ParserError
    {}
  end

  def best_parameters_hash
    return {} if best_parameters.blank?

    JSON.parse(best_parameters)
  rescue JSON::ParserError
    {}
  end

  def best_metrics_hash
    return {} if best_metrics.blank?

    JSON.parse(best_metrics)
  rescue JSON::ParserError
    {}
  end

  def all_results_array
    return [] if all_results.blank?

    JSON.parse(all_results)
  rescue JSON::ParserError
    []
  end

  def sensitivity_analysis_hash
    return {} if sensitivity_analysis.blank?

    JSON.parse(sensitivity_analysis)
  rescue JSON::ParserError
    {}
  end

  def best_score
    return 0 if optimization_metric.blank?

    metric_key = optimization_metric.to_sym
    best_metrics_hash[metric_key] || best_metrics_hash[optimization_metric] || 0
  end

  def top_n_results(n = 10)
    all_results_array.sort_by { |r| -(r['score'] || r[:score] || 0) }.first(n)
  end
end

