# frozen_string_literal: true

class PortfolioCapitalBucket < ApplicationRecord
  belongs_to :portfolio, class_name: "CapitalAllocationPortfolio", foreign_key: "portfolio_id"

  validates :swing_pct, :long_term_pct, :cash_pct, presence: true,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validate :percentages_sum_to_100

  def percentages_sum_to_100
    total = swing_pct + long_term_pct + cash_pct
    return if (total - 100.0).abs < 0.01 # Allow small floating point differences

    errors.add(:base, "Swing, long-term, and cash percentages must sum to 100%")
  end

  def phase
    total = portfolio.total_equity
    return "early" if total < threshold_3l
    return "growth" if total < threshold_5l

    "mature"
  end
end
