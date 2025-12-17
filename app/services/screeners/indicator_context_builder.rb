# frozen_string_literal: true

module Screeners
  # Builds indicator evolution context for AI prompt
  # Extracts last 5 bars of indicator evolution from ScreenerResult
  class IndicatorContextBuilder < ApplicationService
    BARS_TO_INCLUDE = 5

    def self.call(screener_result:)
      new(screener_result: screener_result).call
    end

    def initialize(screener_result:)
      @screener_result = screener_result
      @instrument = screener_result.instrument
    end

    def call
      return nil unless @screener_result.setup_status == "READY"

      # Load daily candles (last 20 to ensure we have enough for indicators)
      daily_series = Candles::Loader.load_latest(
        instrument: @instrument,
        timeframe: "1D",
        count: 20,
      )

      return nil unless daily_series&.candles&.any?

      # Build indicator evolution for last 5 bars
      build_indicator_evolution(daily_series)
    end

    private

    def build_indicator_evolution(series)
      candles = series.candles.last(BARS_TO_INCLUDE)
      return nil if candles.size < BARS_TO_INCLUDE

      # Calculate indicators for each bar
      rsi_evolution = []
      adx_evolution = []
      ema20_distance_evolution = []
      supertrend_evolution = []

      # Calculate EMA20 for the entire series first
      ema20_values = calculate_ema20(series)

      candles.each_with_index do |candle, idx|
        # Find the index of this candle in the full series
        series_idx = series.candles.index(candle)
        next unless series_idx

        # Bar offset (negative: past bars, 0: current bar)
        bar_offset = -(BARS_TO_INCLUDE - idx - 1)

        # Calculate RSI (on partial series up to this index)
        rsi_value = calculate_rsi_at(series, series_idx)
        rsi_evolution << { bar: bar_offset, value: rsi_value.round(2) } if rsi_value

        # Calculate ADX (on partial series up to this index)
        adx_value = calculate_adx_at(series, series_idx)
        adx_evolution << { bar: bar_offset, value: adx_value.round(2) } if adx_value

        # Calculate EMA20 distance % (using pre-calculated EMA20 values)
        if series_idx < ema20_values.size && ema20_values[series_idx] && candle.close
          distance_pct = ((candle.close - ema20_values[series_idx]) / ema20_values[series_idx] * 100).round(2)
          ema20_distance_evolution << { bar: bar_offset, value: distance_pct }
        end

        # Calculate Supertrend (on partial series up to this index)
        supertrend_direction = calculate_supertrend_at(series, series_idx)
        supertrend_evolution << { bar: bar_offset, value: supertrend_direction } if supertrend_direction
      end

      {
        daily: {
          rsi: rsi_evolution,
          adx: adx_evolution,
          ema20_distance_pct: ema20_distance_evolution,
          supertrend: supertrend_evolution,
        },
      }
    end

    def calculate_rsi_at(series, index)
      return nil if index < 14

      partial_series = create_partial_series(series, index)
      partial_series.rsi(14)
    rescue StandardError => e
      Rails.logger.debug("[IndicatorContextBuilder] RSI calculation failed: #{e.message}")
      nil
    end

    def calculate_adx_at(series, index)
      return nil if index < 14

      partial_series = create_partial_series(series, index)
      partial_series.adx(14)
    rescue StandardError => e
      Rails.logger.debug("[IndicatorContextBuilder] ADX calculation failed: #{e.message}")
      nil
    end

    def calculate_ema20(series)
      return [] if series.candles.size < 20

      closes = series.closes
      ema_values = Array.new(series.candles.size, nil)
      multiplier = 2.0 / (20 + 1)

      # First EMA is SMA of first 20 closes
      sma = closes[0..19].sum / 20.0
      ema_values[19] = sma

      # Calculate EMA for remaining candles
      (20...closes.size).each do |i|
        ema = (closes[i] - ema_values[i - 1]) * multiplier + ema_values[i - 1]
        ema_values[i] = ema
      end

      ema_values
    rescue StandardError => e
      Rails.logger.debug("[IndicatorContextBuilder] EMA20 calculation failed: #{e.message}")
      []
    end

    def calculate_supertrend_at(series, index)
      return nil if index < 7

      partial_series = create_partial_series(series, index)
      supertrend_service = Indicators::Supertrend.new(
        series: partial_series,
        period: 7,
        base_multiplier: 3.0,
      )

      result = supertrend_service.call
      return nil unless result && result[:trend]

      # Get trend direction at this index
      close = series.candles[index].close
      supertrend_value = result[:line][index]
      return nil unless close && supertrend_value

      close >= supertrend_value ? "bullish" : "bearish"
    rescue StandardError => e
      Rails.logger.debug("[IndicatorContextBuilder] Supertrend calculation failed: #{e.message}")
      nil
    end

    def create_partial_series(series, index)
      partial_series = CandleSeries.new(symbol: series.symbol, interval: series.interval)
      series.candles[0..index].each { |candle| partial_series.add_candle(candle) }
      partial_series
    end
  end
end
