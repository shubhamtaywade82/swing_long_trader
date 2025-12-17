# frozen_string_literal: true

class SwingPosition < ApplicationRecord
  belongs_to :portfolio, class_name: "CapitalAllocationPortfolio"
  belongs_to :instrument

  validates :entry_price, :quantity, :current_price, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[open closed] }
  validates :stop_loss, numericality: { greater_than: 0 }, allow_nil: true
  validates :take_profit, numericality: { greater_than: 0 }, allow_nil: true

  scope :open, -> { where(status: "open") }
  scope :closed, -> { where(status: "closed") }

  before_save :calculate_unrealized_pnl, if: :will_save_change_to_current_price?

  def open?
    status == "open"
  end

  def closed?
    status == "closed"
  end

  def entry_value
    entry_price * quantity
  end

  def current_value
    current_price * quantity
  end

  def risk_per_share
    return 0 unless stop_loss

    (entry_price - stop_loss).abs
  end

  def risk_amount
    risk_per_share * quantity
  end

  def unrealized_pnl
    (current_price - entry_price) * quantity
  end

  def calculate_unrealized_pnl
    return unless instrument

    # Update current_price from latest candle if available
    # Try daily timeframe first, then intraday
    latest_candle = CandleSeriesRecord.where(instrument_id: instrument.id)
                                       .where(timeframe: :daily)
                                       .order(timestamp: :desc)
                                       .first

    latest_candle ||= CandleSeriesRecord.where(instrument_id: instrument.id)
                                        .order(timestamp: :desc)
                                        .first

    if latest_candle
      self.current_price = latest_candle.close
    end

    self.unrealized_pnl = unrealized_pnl
  end

  def update_current_price!(price)
    self.current_price = price
    self.unrealized_pnl = unrealized_pnl
    save!
  end

  def mark_as_closed!(exit_price:, exit_reason:)
    self.realized_pnl = (exit_price - entry_price) * quantity
    self.exit_price = exit_price
    self.exit_reason = exit_reason
    self.status = "closed"
    self.closed_at = Time.current
    save!

    # Update TradeOutcome if it exists
    update_trade_outcome_on_close(exit_price: exit_price, exit_reason: exit_reason)
  end

  private

  def update_trade_outcome_on_close(exit_price:, exit_reason:)
    outcome = TradeOutcome.find_by(
      position_id: id,
      position_type: "swing_position",
      status: "open",
    )

    return unless outcome

    TradeOutcomes::Updater.call(
      outcome: outcome,
      exit_price: exit_price,
      exit_reason: map_exit_reason(exit_reason),
    )
  end

  def map_exit_reason(reason)
    # Map position exit reasons to TradeOutcome exit reasons
    case reason.to_s.downcase
    when /target|take.profit|tp/
      "target_hit"
    when /stop|sl|stop.loss/
      "stop_hit"
    when /time|holding|days/
      "time_based"
    when /signal|invalid|screener/
      "signal_invalidated"
    else
      "manual"
    end
  end

  def metadata_hash
    return {} if metadata.blank?

    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end
end
