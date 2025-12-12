# frozen_string_literal: true

# ActiveRecord model for storing candle data in the database
# Note: This is separate from the CandleSeries class which is a plain Ruby class
# for working with candle data in memory
class CandleSeriesRecord < ApplicationRecord
  self.table_name = "candle_series"

  belongs_to :instrument

  validates :timeframe, presence: true
  validates :timestamp, presence: true
  validates :open, :high, :low, :close, presence: true, numericality: true
  validates :volume, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :timestamp, uniqueness: { scope: %i[instrument_id timeframe], case_sensitive: true }

  scope :for_instrument, ->(instrument) { where(instrument_id: instrument.id) }
  scope :for_timeframe, ->(timeframe) { where(timeframe: timeframe) }
  scope :recent, ->(limit = 100) { order(timestamp: :desc).limit(limit) }
  scope :ordered, -> { order(timestamp: :asc) }

  # Find candles for a date range
  scope :between_dates, lambda { |from_date, to_date|
    where(timestamp: from_date.beginning_of_day..to_date.end_of_day)
  }

  # Get latest candle for an instrument and timeframe
  def self.latest_for(instrument:, timeframe:)
    for_instrument(instrument)
      .for_timeframe(timeframe)
      .order(timestamp: :desc)
      .first
  end

  # Convert to CandleSeries format (for compatibility with existing code)
  def to_candle
    Candle.new(
      timestamp: timestamp,
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume,
    )
  end
end
