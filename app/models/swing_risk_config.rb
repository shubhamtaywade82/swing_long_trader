# frozen_string_literal: true

class SwingRiskConfig < ApplicationRecord
  belongs_to :portfolio, class_name: "CapitalAllocationPortfolio"

  validates :risk_per_trade, presence: true,
            numericality: { greater_than: 0, less_than_or_equal_to: 5.0 }
  validates :max_position_exposure, presence: true,
            numericality: { greater_than: 0, less_than_or_equal_to: 50.0 }
  validates :max_open_positions, presence: true,
            numericality: { greater_than: 0, less_than_or_equal_to: 20 }
  validates :max_daily_risk, presence: true,
            numericality: { greater_than: 0, less_than_or_equal_to: 10.0 }
  validates :max_portfolio_dd, presence: true,
            numericality: { greater_than: 0, less_than_or_equal_to: 50.0 }

  def risk_per_trade_amount
    portfolio.total_equity * (risk_per_trade / 100.0)
  end

  def max_position_exposure_amount
    portfolio.total_equity * (max_position_exposure / 100.0)
  end

  def max_daily_risk_amount
    portfolio.total_equity * (max_daily_risk / 100.0)
  end
end
