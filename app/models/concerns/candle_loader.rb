# frozen_string_literal: true

module CandleLoader
  extend ActiveSupport::Concern

  included do
    # Add helper methods to Instrument model for loading candles
  end

  # Load daily candles from database as CandleSeries
  # @param limit [Integer, nil] Maximum number of candles to load
  # @param from_date [Date, Time, nil] Start date
  # @param to_date [Date, Time, nil] End date
  # @return [CandleSeries, nil]
  def load_daily_candles(limit: nil, from_date: nil, to_date: nil)
    Candles::Loader.load_for_instrument(
      instrument: self,
      timeframe: "1D",
      limit: limit,
      from_date: from_date,
      to_date: to_date,
    )
  end

  # Load weekly candles from database as CandleSeries
  # @param limit [Integer, nil] Maximum number of candles to load
  # @param from_date [Date, Time, nil] Start date
  # @param to_date [Date, Time, nil] End date
  # @return [CandleSeries, nil]
  def load_weekly_candles(limit: nil, from_date: nil, to_date: nil)
    Candles::Loader.load_for_instrument(
      instrument: self,
      timeframe: "1W",
      limit: limit,
      from_date: from_date,
      to_date: to_date,
    )
  end

  # Load latest N candles for a given timeframe
  # @param timeframe [String] Timeframe ('1D', '1W', '15', '60', '120')
  # @param count [Integer] Number of candles to load
  # @return [CandleSeries, nil]
  def load_candles(timeframe:, count: 100)
    Candles::Loader.load_latest(
      instrument: self,
      timeframe: timeframe,
      count: count,
    )
  end

  # Check if instrument has candles for a given timeframe
  # @param timeframe [String] Timeframe to check
  # @return [Boolean]
  def has_candles?(timeframe:) # rubocop:disable Naming/PredicatePrefix
    CandleSeriesRecord
      .for_instrument(self)
      .for_timeframe(timeframe)
      .exists?
  end

  # Get latest candle timestamp for a given timeframe
  # @param timeframe [String] Timeframe to check
  # @return [Time, nil]
  def latest_candle_timestamp(timeframe:)
    latest = CandleSeriesRecord.latest_for(instrument: self, timeframe: timeframe)
    latest&.timestamp
  end
end
