# frozen_string_literal: true

class LongTermHolding < ApplicationRecord
  belongs_to :portfolio, class_name: "CapitalAllocationPortfolio"
  belongs_to :instrument

  validates :avg_price, :quantity, :allocation_pct, presence: true, numericality: { greater_than: 0 }
  validates :allocation_pct, numericality: { less_than_or_equal_to: 100 }
  validates :portfolio_id, uniqueness: { scope: :instrument_id }

  before_save :update_current_value_and_pnl

  def current_value
    return 0 unless instrument

    # Get latest price from candle data
    latest_candle = CandleSeriesRecord.where(instrument_id: instrument.id)
                                       .where(timeframe: "1D")
                                       .order(timestamp: :desc)
                                       .first

    latest_candle ||= CandleSeriesRecord.where(instrument_id: instrument.id)
                                        .order(timestamp: :desc)
                                        .first

    current_price = latest_candle&.close || avg_price
    current_price * quantity
  end

  def cost_basis
    avg_price * quantity
  end

  def unrealized_pnl
    current_value - cost_basis
  end

  def unrealized_pnl_pct
    return 0 if cost_basis.zero?

    (unrealized_pnl / cost_basis * 100).round(2)
  end

  def update_current_value_and_pnl
    self.current_value = current_value
    self.unrealized_pnl = unrealized_pnl
  end

  def needs_rebalance?(target_allocation_pct:)
    current_allocation = (current_value / portfolio.total_equity * 100).round(2)
    (current_allocation - target_allocation_pct).abs > 2.0 # 2% threshold
  end

  def metadata_hash
    return {} if metadata.blank?

    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end
end
