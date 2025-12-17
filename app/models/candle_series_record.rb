# frozen_string_literal: true

# ActiveRecord model for storing candle data in the database
# Note: This is separate from the CandleSeries class which is a plain Ruby class
# for working with candle data in memory
class CandleSeriesRecord < ApplicationRecord
  self.table_name = "candle_series"

  belongs_to :instrument

  # Enum for candle timeframes
  # - daily (0): End-of-day candles, typically 1D
  # - weekly (1): Weekly aggregated candles, typically 1W
  # - hourly (2): Hourly candles, typically 1H or 60-minute intervals
  enum :timeframe, {
    daily: 0,
    weekly: 1,
    hourly: 2
  }

  validates :timeframe, presence: true
  validates :timestamp, presence: true
  validates :open, :high, :low, :close, presence: true, numericality: true
  validates :volume, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :timestamp, uniqueness: { scope: %i[instrument_id timeframe], case_sensitive: true }

  # Default scope orders by timestamp ascending to match technical analysis gem requirements.
  # Both ruby-technical-analysis and technical-analysis gems expect chronological order
  # (oldest to newest). This ensures consistent data ordering across the application.
  # Note: Queries needing descending order should explicitly use .order(timestamp: :desc)
  # which will override this default scope.
  default_scope { order(timestamp: :asc) }

  scope :for_instrument, ->(instrument) { where(instrument_id: instrument.id) }
  scope :recent, ->(limit = 100) { order(timestamp: :desc).limit(limit) }
  # Note: This scope is redundant with default_scope but kept for explicit clarity
  # when reading code that uses .ordered
  scope :ordered, -> { order(timestamp: :asc) }

  # Find candles for a date range
  scope :between_dates, lambda { |from_date, to_date|
    where(timestamp: from_date.beginning_of_day..to_date.end_of_day)
  }

  # Get latest candle for an instrument and timeframe
  # @param timeframe [Symbol] Enum symbol (:daily, :weekly, :hourly)
  # @raise [ArgumentError] if timeframe is not a valid enum value
  # Find the latest candle for a given instrument and timeframe
  #
  # @param instrument [Instrument] The instrument to query
  # @param timeframe [Symbol] The timeframe enum key (:daily, :weekly, :hourly)
  # @return [CandleSeriesRecord, nil] The latest candle record or nil if none exists
  # @raise [ArgumentError] if timeframe is not a valid enum key
  def self.latest_for(instrument:, timeframe:)
    unless timeframes.key?(timeframe)
      raise ArgumentError, "Invalid timeframe: #{timeframe}. Must be one of: #{timeframes.keys.join(', ')}"
    end

    for_instrument(instrument)
      .public_send(timeframe)
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
