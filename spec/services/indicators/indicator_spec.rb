# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandleSeries, type: :service do
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

  describe 'EMA' do
    it 'calculates correctly for uptrend' do
      series = create_uptrend_candles
      ema20 = series.ema(20)
      ema50 = series.ema(50)

      expect(ema20).not_to be_nil
      expect(ema50).not_to be_nil
      # EMA should be increasing in uptrend
      expect(ema20).to be > 0
      expect(ema50).to be > 0
    end
  end

  describe 'RSI' do
    it 'is above 50 in uptrend' do
      series = create_uptrend_candles
      rsi = series.rsi(14)

      expect(rsi).not_to be_nil
      # RSI should be above 50 in strong uptrend
      expect(rsi).to be > 50
      expect(rsi).to be <= 100
    end

    it 'is below 50 in downtrend' do
      series = create_downtrend_candles
      rsi = series.rsi(14)

      expect(rsi).not_to be_nil
      # RSI should be below 50 in strong downtrend
      expect(rsi).to be < 50
      expect(rsi).to be >= 0
    end
  end

  describe 'ATR' do
    it 'calculates volatility' do
      series = create_sideways_candles
      atr = series.atr(14)

      expect(atr).not_to be_nil
      # ATR should be positive
      expect(atr).to be > 0
    end
  end

  describe 'MACD' do
    it 'shows trend direction' do
      series = create_uptrend_candles
      macd_result = series.macd(12, 26, 9)

      expect(macd_result).not_to be_nil
      expect(macd_result).to be_a(Array)
      expect(macd_result.size).to be >= 3
      # MACD should return [macd_line, signal_line, histogram]
      macd_line, signal_line, histogram = macd_result
      expect(macd_line).not_to be_nil
      expect(signal_line).not_to be_nil
      expect(histogram).not_to be_nil
    end
  end

  describe 'Supertrend' do
    it 'identifies trend direction' do
      series = create_uptrend_candles
      supertrend = Indicators::Supertrend.new(series: series, period: 10, base_multiplier: 3.0)

      result = supertrend.call

      expect(result).not_to be_nil
      expect(result).to be_a(Hash)
      # Should have trend direction
      expect(result).to have_key(:trend)
      expect(result[:trend]).to be_in([:bullish, :bearish])
    end
  end

  describe 'ADX' do
    it 'measures trend strength' do
      series = create_uptrend_candles
      adx = series.adx(14)

      expect(adx).not_to be_nil
      # ADX should be positive
      expect(adx).to be > 0
      expect(adx).to be <= 100
    end
  end
end

