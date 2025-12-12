# frozen_string_literal: true

# Helper methods for indicator tasks
module IndicatorHelpers
  module_function

  def find_instrument_with_candles
    # Use CandleSeriesRecord directly since association might not be loaded
    candle_record = CandleSeriesRecord.for_timeframe('1D').first
    return nil unless candle_record

    instrument = candle_record.instrument
    unless instrument
      puts "❌ No instruments with daily candles found in database"
      puts "   Run: rails candles:daily:ingest first"
      return nil
    end

    instrument
  end

  def test_indicators(series)
    last_index = series.candles.size - 1

    # Test EMA
    puts "📈 EMA Test:"
    ema20 = series.ema(20)
    ema50 = series.ema(50)
    if ema20 && ema50
      puts "   ✅ EMA(20): #{ema20.round(2)}, EMA(50): #{ema50.round(2)}"
    else
      puts "   ❌ EMA calculation failed"
    end
    puts ""

    # Test RSI
    puts "📈 RSI Test:"
    rsi = series.rsi(14)
    if rsi
      puts "   ✅ RSI(14): #{rsi.round(2)}"
    else
      puts "   ❌ RSI calculation failed"
    end
    puts ""

    # Test Supertrend
    puts "📈 Supertrend Test:"
    begin
      supertrend = Indicators::Supertrend.new(series: series, period: 10, base_multiplier: 3.0)
      result = supertrend.call
      if result && result[:trend]
        puts "   ✅ Supertrend: #{result[:trend]}"
      else
        puts "   ❌ Supertrend calculation failed"
      end
    rescue StandardError => e
      puts "   ❌ Error: #{e.message}"
    end
    puts ""

    # Test ADX
    puts "📈 ADX Test:"
    adx = series.adx(14)
    if adx
      puts "   ✅ ADX(14): #{adx.round(2)}"
    else
      puts "   ❌ ADX calculation failed"
    end
    puts ""

    # Test MACD
    puts "📈 MACD Test:"
    macd_result = series.macd(12, 26, 9)
    if macd_result && macd_result.is_a?(Array) && macd_result.size >= 3
      puts "   ✅ MACD calculated successfully"
    else
      puts "   ❌ MACD calculation failed"
    end
    puts ""

    # Test ATR
    puts "📈 ATR Test:"
    atr = series.atr(14)
    if atr
      puts "   ✅ ATR(14): #{atr.round(2)}"
    else
      puts "   ❌ ATR calculation failed"
    end
    puts ""

    # Test Indicator Wrappers
    puts "📈 Indicator Wrappers Test:"
    test_indicator_wrappers(series, last_index)
  end

  def test_indicator_wrappers(series, index)
    # Test RSI Indicator
    begin
      rsi_indicator = Indicators::RsiIndicator.new(series: series, config: { period: 14 })
      if rsi_indicator.ready?(index)
        rsi_result = rsi_indicator.calculate_at(index)
        if rsi_result
          puts "   ✅ RSI Indicator: #{rsi_result[:value].round(2)}, " \
               "Direction: #{rsi_result[:direction]}, " \
               "Confidence: #{rsi_result[:confidence]}"
        else
          puts "   ⚠️  RSI Indicator: No signal"
        end
      else
        puts "   ⚠️  RSI Indicator: Not ready (need #{rsi_indicator.min_required_candles} candles)"
      end
    rescue StandardError => e
      puts "   ❌ RSI Indicator Error: #{e.message}"
    end

    # Test Supertrend Indicator
    begin
      st_indicator = Indicators::SupertrendIndicator.new(series: series, config: { period: 10 })
      if st_indicator.ready?(index)
        st_result = st_indicator.calculate_at(index)
        if st_result
          puts "   ✅ Supertrend Indicator: Direction: #{st_result[:direction]}, " \
               "Confidence: #{st_result[:confidence]}"
        else
          puts "   ⚠️  Supertrend Indicator: No signal"
        end
      else
        puts "   ⚠️  Supertrend Indicator: Not ready"
      end
    rescue StandardError => e
      puts "   ❌ Supertrend Indicator Error: #{e.message}"
    end
  end
end

namespace :indicators do
  desc 'Test indicators with sample instrument (requires candles in DB)'
  task test: :environment do
    # Find an instrument with candles
    candle_record = CandleSeriesRecord.for_timeframe('1D').first
    unless candle_record
      puts "❌ No instruments with daily candles found in database"
      puts "   Run: rails candles:daily:ingest first"
      exit 1
    end

    instrument = candle_record.instrument

    puts "📊 Testing indicators for: #{instrument.symbol_name}"
    puts "=" * 60

    # Load daily candles
    daily_series = instrument.load_daily_candles(limit: 100)
    unless daily_series
      puts "❌ Failed to load daily candles"
      exit 1
    end

    puts "✅ Loaded #{daily_series.candles.size} daily candles"
    puts ""

    # Test each indicator
    IndicatorHelpers.test_indicators(daily_series)
  end

  desc 'Test EMA calculation'
  task test_ema: :environment do
    instrument = IndicatorHelpers.find_instrument_with_candles
    return unless instrument

    series = instrument.load_daily_candles(limit: 50)
    return unless series

    puts "📈 Testing EMA for: #{instrument.symbol_name}"
    puts "   Candles: #{series.candles.size}"

    ema20 = series.ema(20)
    ema50 = series.ema(50)

    if ema20 && ema50
      puts "   ✅ EMA(20): #{ema20.round(2)}"
      puts "   ✅ EMA(50): #{ema50.round(2)}"
      puts "   Trend: #{ema20 > ema50 ? 'Bullish' : 'Bearish'}"
    else
      puts "   ❌ EMA calculation failed"
    end
  end

  desc 'Test RSI calculation'
  task test_rsi: :environment do
    instrument = IndicatorHelpers.find_instrument_with_candles
    return unless instrument

    series = instrument.load_daily_candles(limit: 50)
    return unless series

    puts "📈 Testing RSI for: #{instrument.symbol_name}"
    puts "   Candles: #{series.candles.size}"

    rsi = series.rsi(14)
    if rsi
      puts "   ✅ RSI(14): #{rsi.round(2)}"
      status = if rsi < 30
                 'Oversold'
               elsif rsi > 70
                 'Overbought'
               else
                 'Neutral'
               end
      puts "   Status: #{status}"
    else
      puts "   ❌ RSI calculation failed"
    end
  end

  desc 'Test Supertrend calculation'
  task test_supertrend: :environment do
    instrument = IndicatorHelpers.find_instrument_with_candles
    return unless instrument

    series = instrument.load_daily_candles(limit: 50)
    return unless series

    puts "📈 Testing Supertrend for: #{instrument.symbol_name}"
    puts "   Candles: #{series.candles.size}"

    begin
      supertrend = Indicators::Supertrend.new(series: series, period: 10, base_multiplier: 3.0)
      result = supertrend.call

      if result && result[:trend]
        puts "   ✅ Supertrend calculated"
        puts "   Trend: #{result[:trend]}"
        puts "   Latest value: #{result[:line].last.round(2)}" if result[:line]&.last
      else
        puts "   ❌ Supertrend calculation failed"
      end
    rescue StandardError => e
      puts "   ❌ Error: #{e.message}"
    end
  end

  desc 'Test ADX calculation'
  task test_adx: :environment do
    instrument = IndicatorHelpers.find_instrument_with_candles
    return unless instrument

    series = instrument.load_daily_candles(limit: 50)
    return unless series

    puts "📈 Testing ADX for: #{instrument.symbol_name}"
    puts "   Candles: #{series.candles.size}"

    adx = series.adx(14)
    if adx
      puts "   ✅ ADX(14): #{adx.round(2)}"
      strength = if adx > 25
                   'Strong Trend'
                 elsif adx > 20
                   'Moderate Trend'
                 else
                   'Weak Trend'
                 end
      puts "   Strength: #{strength}"
    else
      puts "   ❌ ADX calculation failed"
    end
  end

  desc 'Test MACD calculation'
  task test_macd: :environment do
    instrument = IndicatorHelpers.find_instrument_with_candles
    return unless instrument

    series = instrument.load_daily_candles(limit: 50)
    return unless series

    puts "📈 Testing MACD for: #{instrument.symbol_name}"
    puts "   Candles: #{series.candles.size}"

    macd_result = series.macd(12, 26, 9)
    if macd_result && macd_result.is_a?(Array) && macd_result.size >= 3
      macd_line, signal_line, histogram = macd_result
      puts "   ✅ MACD Line: #{macd_line.round(4)}"
      puts "   ✅ Signal Line: #{signal_line.round(4)}"
      puts "   ✅ Histogram: #{histogram.round(4)}"
      puts "   Signal: #{macd_line > signal_line ? 'Bullish' : 'Bearish'}"
    else
      puts "   ❌ MACD calculation failed"
    end
  end

  desc 'Test ATR calculation'
  task test_atr: :environment do
    instrument = IndicatorHelpers.find_instrument_with_candles
    return unless instrument

    series = instrument.load_daily_candles(limit: 50)
    return unless series

    puts "📈 Testing ATR for: #{instrument.symbol_name}"
    puts "   Candles: #{series.candles.size}"

    atr = series.atr(14)
    if atr
      puts "   ✅ ATR(14): #{atr.round(2)}"
      latest_close = series.candles.last&.close
      if latest_close
        atr_pct = (atr / latest_close * 100).round(2)
        puts "   ATR %: #{atr_pct}%"
      end
    else
      puts "   ❌ ATR calculation failed"
    end
  end
end

