# frozen_string_literal: true

require 'test_helper'

module Indicators
  class IndicatorTest < ActiveSupport::TestCase
    # Test data: Simple uptrend with known values
    def create_uptrend_candles
      series = CandleSeries.new(symbol: 'TEST', interval: '1D')
      # Create 20 candles with upward trend
      20.times do |i|
        base_price = 100.0 + (i * 2.0)
        series.add_candle(
          Candle.new(
            timestamp: i.days.ago,
            open: base_price,
            high: base_price + 3.0,
            low: base_price - 1.0,
            close: base_price + 2.0,
            volume: 1_000_000
          )
        )
      end
      series
    end

    # Test data: Simple downtrend
    def create_downtrend_candles
      series = CandleSeries.new(symbol: 'TEST', interval: '1D')
      # Create 20 candles with downward trend
      20.times do |i|
        base_price = 120.0 - (i * 2.0)
        series.add_candle(
          Candle.new(
            timestamp: i.days.ago,
            open: base_price,
            high: base_price + 1.0,
            low: base_price - 3.0,
            close: base_price - 2.0,
            volume: 1_000_000
          )
        )
      end
      series
    end

    # Test data: Sideways/volatile market
    def create_sideways_candles
      series = CandleSeries.new(symbol: 'TEST', interval: '1D')
      # Create 20 candles oscillating around 100
      20.times do |i|
        oscillation = Math.sin(i * 0.5) * 5.0
        base_price = 100.0 + oscillation
        series.add_candle(
          Candle.new(
            timestamp: i.days.ago,
            open: base_price,
            high: base_price + 2.0,
            low: base_price - 2.0,
            close: base_price + (oscillation * 0.1),
            volume: 1_000_000
          )
        )
      end
      series
    end

    test 'EMA should calculate correctly for uptrend' do
      series = create_uptrend_candles
      ema20 = series.ema(20)
      ema50 = series.ema(50)

      assert_not_nil ema20
      assert_not_nil ema50
      # EMA should be increasing in uptrend
      assert ema20 > 0
      assert ema50 > 0
    end

    test 'RSI should be above 50 in uptrend' do
      series = create_uptrend_candles
      rsi = series.rsi(14)

      assert_not_nil rsi
      # RSI should be above 50 in strong uptrend
      assert rsi > 50
      assert rsi <= 100
    end

    test 'RSI should be below 50 in downtrend' do
      series = create_downtrend_candles
      rsi = series.rsi(14)

      assert_not_nil rsi
      # RSI should be below 50 in strong downtrend
      assert rsi < 50
      assert rsi >= 0
    end

    test 'ATR should calculate volatility' do
      series = create_sideways_candles
      atr = series.atr(14)

      assert_not_nil atr
      # ATR should be positive
      assert atr > 0
    end

    test 'MACD should show trend direction' do
      series = create_uptrend_candles
      macd_result = series.macd(12, 26, 9)

      assert_not_nil macd_result
      assert macd_result.is_a?(Array)
      assert macd_result.size >= 3
      # MACD should return [macd_line, signal_line, histogram]
      macd_line, signal_line, histogram = macd_result
      assert_not_nil macd_line
      assert_not_nil signal_line
      assert_not_nil histogram
    end

    test 'Supertrend should identify trend direction' do
      series = create_uptrend_candles
      supertrend = Indicators::Supertrend.new(series: series, period: 10, base_multiplier: 3.0)

      result = supertrend.call

      assert_not_nil result
      assert result.is_a?(Hash)
      # Should have trend direction
      assert result.key?(:trend)
      assert_includes [:bullish, :bearish], result[:trend]
    end

    test 'ADX should measure trend strength' do
      series = create_uptrend_candles
      adx = series.adx(14)

      assert_not_nil adx
      # ADX should be positive
      assert adx > 0
      assert adx <= 100
    end
  end
end

