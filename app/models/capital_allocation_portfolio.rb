# frozen_string_literal: true

class CapitalAllocationPortfolio < ApplicationRecord
  self.table_name = "capital_allocation_portfolios"

  has_many :swing_positions, dependent: :destroy
  has_many :long_term_holdings, dependent: :destroy
  has_many :ledger_entries, dependent: :destroy
  has_one :swing_risk_config, dependent: :destroy
  has_one :capital_bucket, class_name: "PortfolioCapitalBucket", dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :mode, inclusion: { in: %w[paper live] }
  validates :total_equity, :available_cash, :swing_capital, :long_term_capital,
            :realized_pnl, :unrealized_pnl, :max_drawdown, :peak_equity,
            numericality: { greater_than_or_equal_to: 0 }

  scope :paper, -> { where(mode: "paper") }
  scope :live, -> { where(mode: "live") }
  scope :active, -> { where.not(name: nil) }

  after_create :initialize_capital_buckets
  after_create :initialize_risk_config

  def paper?
    mode == "paper"
  end

  def live?
    mode == "live"
  end

  def open_swing_positions
    swing_positions.where(status: "open")
  end

  def closed_swing_positions
    swing_positions.where(status: "closed")
  end

  def total_swing_exposure
    open_swing_positions.sum("entry_price * quantity")
  end

  def total_long_term_value
    long_term_holdings.sum(&:current_value)
  end

  def update_equity!
    # Recalculate unrealized P&L from positions
    swing_unrealized = open_swing_positions.sum(&:unrealized_pnl)
    long_term_unrealized = long_term_holdings.sum(&:unrealized_pnl)

    total_unrealized = swing_unrealized + long_term_unrealized

    # Total equity = cash + swing capital + long_term capital
    # But also includes unrealized P&L
    new_total_equity = available_cash + swing_capital + long_term_capital + total_unrealized

    update!(
      total_equity: new_total_equity,
      unrealized_pnl: total_unrealized,
      peak_equity: [peak_equity, new_total_equity].max,
    )

    update_drawdown!
  end

  def update_drawdown!
    return if peak_equity.zero?

    current_equity = total_equity
    drawdown = ((peak_equity - current_equity) / peak_equity * 100).round(2)

    update!(max_drawdown: [max_drawdown, drawdown].max)
  end

  def available_swing_capital
    swing_capital - total_swing_exposure
  end

  def available_long_term_capital
    long_term_capital - total_long_term_value
  end

  def rebalance_capital!
    bucket = capital_bucket || create_capital_bucket!
    total = total_equity

    # Determine phase based on total equity
    if total < bucket.threshold_3l
      # Early stage: < ₹3L
      swing_pct = 80.0
      long_term_pct = 0.0
      cash_pct = 20.0
    elsif total < bucket.threshold_5l
      # Growth phase: ₹3L - ₹5L
      swing_pct = 70.0
      long_term_pct = 20.0
      cash_pct = 10.0
    else
      # Mature phase: ₹5L+
      swing_pct = 60.0
      long_term_pct = 30.0
      cash_pct = 10.0
    end

    # Update bucket percentages
    bucket.update!(
      swing_pct: swing_pct,
      long_term_pct: long_term_pct,
      cash_pct: cash_pct,
    )

    # Recalculate capital allocation
    new_swing_capital = (total * swing_pct / 100.0).round(2)
    new_long_term_capital = (total * long_term_pct / 100.0).round(2)
    new_cash = (total * cash_pct / 100.0).round(2)

    # Adjust for existing positions
    swing_exposure = total_swing_exposure
    long_term_value = total_long_term_value

    # Ensure we don't go negative
    if swing_exposure > new_swing_capital
      new_swing_capital = swing_exposure
      new_cash = total - new_swing_capital - new_long_term_capital
    end

    if long_term_value > new_long_term_capital
      new_long_term_capital = long_term_value
      new_cash = total - new_swing_capital - new_long_term_capital
    end

    update!(
      swing_capital: new_swing_capital,
      long_term_capital: new_long_term_capital,
      available_cash: new_cash,
    )

    # Record in ledger
    ledger_entries.create!(
      amount: total,
      reason: "capital_rebalance",
      entry_type: "credit",
      metadata: {
        swing_pct: swing_pct,
        long_term_pct: long_term_pct,
        cash_pct: cash_pct,
        phase: total < bucket.threshold_3l ? "early" : (total < bucket.threshold_5l ? "growth" : "mature"),
      }.to_json,
    )
  end

  private

  def initialize_capital_buckets
    create_capital_bucket! unless capital_bucket
  end

  def initialize_risk_config
    create_swing_risk_config! unless swing_risk_config
  end
end
