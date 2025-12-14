# frozen_string_literal: true

class TradeOutcome < ApplicationRecord
  belongs_to :screener_run
  belongs_to :instrument

  validates :symbol, presence: true
  validates :trading_mode, presence: true, inclusion: { in: %w[paper live] }
  validates :entry_price, presence: true, numericality: { greater_than: 0 }
  validates :entry_time, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[open closed cancelled] }
  validates :exit_reason, inclusion: {
    in: %w[target_hit stop_hit manual time_based signal_invalidated],
    allow_nil: true,
  }

  scope :open, -> { where(status: "open") }
  scope :closed, -> { where(status: "closed") }
  scope :cancelled, -> { where(status: "cancelled") }
  scope :paper, -> { where(trading_mode: "paper") }
  scope :live, -> { where(trading_mode: "live") }
  scope :by_run, ->(run_id) { where(screener_run_id: run_id) }
  scope :winners, -> { closed.where("pnl > 0") }
  scope :losers, -> { closed.where("pnl < 0") }
  scope :breakeven, -> { closed.where("pnl = 0") }

  # Performance scopes
  scope :profitable, -> { closed.where("r_multiple > 0") }
  scope :high_r_multiple, ->(threshold = 2.0) { closed.where("r_multiple >= ?", threshold) }
  scope :by_tier, ->(tier) { where(tier: tier) }
  scope :by_ai_confidence_range, ->(min, max) { where(ai_confidence: min..max) }

  before_save :calculate_metrics, if: :will_save_change_to_exit_price?

  def open?
    status == "open"
  end

  def closed?
    status == "closed"
  end

  def cancelled?
    status == "cancelled"
  end

  def winner?
    closed? && pnl&.positive?
  end

  def loser?
    closed? && pnl&.negative?
  end

  def breakeven?
    closed? && pnl&.zero?
  end

  def entry_value
    entry_price * quantity
  end

  def exit_value
    return nil unless exit_price

    exit_price * quantity
  end

  def calculate_metrics
    return unless exit_price && entry_price

    # Calculate P&L
    self.pnl = (exit_price - entry_price) * quantity

    # Calculate P&L percentage
    self.pnl_percent = entry_price.positive? ? ((exit_price - entry_price) / entry_price * 100) : 0

    # Calculate R-multiple
    if risk_per_share&.positive?
      self.r_multiple = (pnl / (risk_per_share * quantity)).round(2)
    elsif risk_amount&.positive?
      self.r_multiple = (pnl / risk_amount).round(2)
    end

    # Calculate holding days
    if entry_time && exit_time
      self.holding_days = ((exit_time - entry_time) / 1.day).round
    end
  end

  def mark_closed!(exit_price:, exit_reason:, exit_time: nil)
    self.exit_price = exit_price
    self.exit_reason = exit_reason
    self.exit_time = exit_time || Time.current
    self.status = "closed"
    calculate_metrics
    save!
  end

  def mark_cancelled!(reason: nil)
    self.status = "cancelled"
    self.notes = [notes, "Cancelled: #{reason}"].compact.join("\n")
    save!
  end

  # Class methods for analysis
  def self.win_rate(scope = all)
    closed_trades = scope.closed
    return 0 if closed_trades.empty?

    (closed_trades.winners.count.to_f / closed_trades.count * 100).round(2)
  end

  def self.average_r_multiple(scope = all)
    closed_trades = scope.closed.where.not(r_multiple: nil)
    return 0 if closed_trades.empty?

    closed_trades.average(:r_multiple)&.round(2) || 0
  end

  def self.expectancy(scope = all)
    closed_trades = scope.closed.where.not(r_multiple: nil)
    return 0 if closed_trades.empty?

    win_rate_pct = win_rate(closed_trades) / 100.0
    avg_win_r = closed_trades.winners.average(:r_multiple)&.to_f || 0
    avg_loss_r = closed_trades.losers.average(:r_multiple)&.to_f || 0

    (win_rate_pct * avg_win_r) + ((1 - win_rate_pct) * avg_loss_r)
  end

  def self.by_ai_confidence_bucket(scope = all)
    closed_trades = scope.closed
    {
      high: closed_trades.where("ai_confidence >= 8.0"),
      medium: closed_trades.where("ai_confidence >= 6.5 AND ai_confidence < 8.0"),
      low: closed_trades.where("ai_confidence < 6.5"),
    }
  end
end
