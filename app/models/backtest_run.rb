# frozen_string_literal: true

class BacktestRun < ApplicationRecord
  has_many :backtest_positions, dependent: :destroy

  validates :start_date, :end_date, :strategy_type, :initial_capital, :risk_per_trade, presence: true
  validates :strategy_type, inclusion: { in: %w[swing long_term] }
  validates :status, inclusion: { in: %w[pending running completed failed] }

  scope :completed, -> { where(status: 'completed') }
  scope :swing, -> { where(strategy_type: 'swing') }
  scope :long_term, -> { where(strategy_type: 'long_term') }

  def config_hash
    return {} if config.blank?

    JSON.parse(config)
  rescue JSON::ParserError
    {}
  end

  def results_hash
    return {} if results.blank?

    JSON.parse(results)
  rescue JSON::ParserError
    {}
  end
end

