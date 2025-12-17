# frozen_string_literal: true

# Rails console script to find latest candle for any instrument
# Usage in Rails console:
#   load 'lib/console_scripts/find_latest_candle.rb'
#   find_latest_candle('RELIANCE')
#   find_latest_candle_by_id(1)
#   find_latest_candle_all_timeframes('TCS')
#   find_latest_candles_bulk(['RELIANCE', 'TCS', 'INFY'])

# Find latest candle for an instrument by symbol
# @param symbol [String] Instrument symbol (e.g., 'RELIANCE', 'TCS')
# @param timeframe [String] Timeframe ('1D', '1W', '15', '60', '120') - default: '1D'
# @return [Hash] Latest candle information
def find_latest_candle(symbol, timeframe: "1D")
  instrument = Instrument.find_by(symbol_name: symbol)
  unless instrument
    puts "❌ Instrument '#{symbol}' not found"
    return nil
  end

  latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: timeframe)
  unless latest
    puts "❌ No #{timeframe} candles found for #{symbol}"
    return nil
  end

  days_ago = (Time.zone.today - latest.timestamp.to_date).to_i
  is_fresh = days_ago <= 2

  result = {
    symbol: symbol,
    instrument_id: instrument.id,
    timeframe: timeframe,
    latest_candle: {
      date: latest.timestamp.to_date,
      timestamp: latest.timestamp,
      open: latest.open,
      high: latest.high,
      low: latest.low,
      close: latest.close,
      volume: latest.volume,
      days_ago: days_ago,
      is_fresh: is_fresh,
    },
    instrument_info: {
      symbol_name: instrument.symbol_name,
      display_name: instrument.display_name,
      segment: instrument.segment,
      security_id: instrument.security_id,
    },
  }

  puts "\n📊 Latest #{timeframe} Candle for #{symbol}:"
  puts "   Date: #{latest.timestamp.to_date} (#{days_ago} days ago) #{is_fresh ? '✅' : '❌'}"
  puts "   OHLC: O=₹#{latest.open.round(2)} H=₹#{latest.high.round(2)} L=₹#{latest.low.round(2)} C=₹#{latest.close.round(2)}"
  puts "   Volume: #{latest.volume.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
  puts "   Instrument ID: #{instrument.id} | Security ID: #{instrument.security_id}"

  result
end

# Find latest candle for an instrument by ID
# @param instrument_id [Integer] Instrument ID
# @param timeframe [String] Timeframe ('1D', '1W', '15', '60', '120') - default: '1D'
# @return [Hash] Latest candle information
def find_latest_candle_by_id(instrument_id, timeframe: "1D")
  instrument = Instrument.find_by(id: instrument_id)
  unless instrument
    puts "❌ Instrument with ID #{instrument_id} not found"
    return nil
  end

  find_latest_candle(instrument.symbol_name, timeframe: timeframe)
end

# Find latest candles for all timeframes for an instrument
# @param symbol [String] Instrument symbol
# @return [Hash] Latest candles for all timeframes
def find_latest_candle_all_timeframes(symbol)
  instrument = Instrument.find_by(symbol_name: symbol)
  unless instrument
    puts "❌ Instrument '#{symbol}' not found"
    return nil
  end

  timeframes = %w[1D 1W 15 60 120]
  results = {}

  puts "\n📊 Latest Candles for #{symbol} (All Timeframes):"
  puts "=" * 60

  timeframes.each do |tf|
    latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: tf)
    if latest
      days_ago = (Time.zone.today - latest.timestamp.to_date).to_i
      is_fresh = days_ago <= 2
      status = is_fresh ? "✅" : "❌"

      puts "\n#{tf}:"
      puts "   Date: #{latest.timestamp.to_date} (#{days_ago} days ago) #{status}"
      puts "   Close: ₹#{latest.close.round(2)} | Volume: #{latest.volume.to_s.reverse.gsub(/(\d{3})(?=\d)/,
                                                                                            '\\1,').reverse}"

      results[tf] = {
        date: latest.timestamp.to_date,
        close: latest.close,
        volume: latest.volume,
        days_ago: days_ago,
        is_fresh: is_fresh,
      }
    else
      puts "\n#{tf}: ❌ No candles found"
      results[tf] = nil
    end
  end

  results
end

# Find latest candles for multiple instruments
# @param symbols [Array<String>] Array of instrument symbols
# @param timeframe [String] Timeframe ('1D', '1W', '15', '60', '120') - default: '1D'
# @return [Hash] Latest candles for all instruments
def find_latest_candles_bulk(symbols, timeframe: "1D")
  results = {}

  puts "\n📊 Latest #{timeframe} Candles for Multiple Instruments:"
  puts "=" * 80

  symbols.each do |symbol|
    instrument = Instrument.find_by(symbol_name: symbol)
    unless instrument
      puts "#{symbol}: ❌ Not found"
      results[symbol] = nil
      next
    end

    latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: timeframe)
    if latest
      days_ago = (Time.zone.today - latest.timestamp.to_date).to_i
      is_fresh = days_ago <= 2
      status = is_fresh ? "✅" : "❌"

      puts "#{symbol.ljust(20)} | Date: #{latest.timestamp.to_date.to_s.ljust(12)} | Close: ₹#{latest.close.round(2).to_s.rjust(10)} | #{days_ago.to_s.rjust(3)} days ago #{status}"

      results[symbol] = {
        date: latest.timestamp.to_date,
        close: latest.close,
        days_ago: days_ago,
        is_fresh: is_fresh,
      }
    else
      puts "#{symbol.ljust(20)} | ❌ No candles found"
      results[symbol] = nil
    end
  end

  results
end

# Find instruments with the oldest/stalest candles
# @param timeframe [String] Timeframe ('1D', '1W') - default: '1D'
# @param limit [Integer] Number of results to return - default: 10
# @return [Array<Hash>] Instruments with oldest candles
def find_stalest_candles(timeframe: "1D", limit: 10)
  instruments = Instrument.where(segment: %w[equity index]).limit(500)
  stalest = []

  puts "\n📊 Finding #{limit} Instruments with Stalest #{timeframe} Candles:"
  puts "=" * 80

  instruments.find_each do |instrument|
    latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: timeframe)
    next unless latest

    days_ago = (Time.zone.today - latest.timestamp.to_date).to_i
    stalest << {
      symbol: instrument.symbol_name,
      instrument_id: instrument.id,
      latest_date: latest.timestamp.to_date,
      days_ago: days_ago,
      close: latest.close,
    }
  end

  stalest.sort_by! { |x| -x[:days_ago] }
  stalest.first(limit).each_with_index do |item, index|
    puts "#{(index + 1).to_s.rjust(3)}. #{item[:symbol].ljust(25)} | Date: #{item[:latest_date]} | #{item[:days_ago].to_s.rjust(4)} days ago | Close: ₹#{item[:close].round(2)}"
  end

  stalest.first(limit)
end

# Find instruments with the freshest candles
# @param timeframe [String] Timeframe ('1D', '1W') - default: '1D'
# @param limit [Integer] Number of results to return - default: 10
# @return [Array<Hash>] Instruments with freshest candles
def find_freshest_candles(timeframe: "1D", limit: 10)
  instruments = Instrument.where(segment: %w[equity index]).limit(500)
  freshest = []

  puts "\n📊 Finding #{limit} Instruments with Freshest #{timeframe} Candles:"
  puts "=" * 80

  instruments.find_each do |instrument|
    latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: timeframe)
    next unless latest

    days_ago = (Time.zone.today - latest.timestamp.to_date).to_i
    freshest << {
      symbol: instrument.symbol_name,
      instrument_id: instrument.id,
      latest_date: latest.timestamp.to_date,
      days_ago: days_ago,
      close: latest.close,
    }
  end

  freshest.sort_by! { |x| x[:days_ago] }
  freshest.first(limit).each_with_index do |item, index|
    status = item[:days_ago] <= 2 ? "✅" : "❌"
    puts "#{(index + 1).to_s.rjust(3)}. #{item[:symbol].ljust(25)} | Date: #{item[:latest_date]} | #{item[:days_ago].to_s.rjust(4)} days ago #{status} | Close: ₹#{item[:close].round(2)}"
  end

  freshest.first(limit)
end

# Get summary statistics for candles
# @param timeframe [String] Timeframe ('1D', '1W') - default: '1D'
# @return [Hash] Summary statistics
def candle_summary_stats(timeframe: "1D")
  instruments = Instrument.where(segment: %w[equity index])
  total = instruments.count
  with_candles = 0
  without_candles = 0
  days_ago_list = []

  instruments.find_each do |instrument|
    latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: timeframe)
    if latest
      with_candles += 1
      days_ago = (Time.zone.today - latest.timestamp.to_date).to_i
      days_ago_list << days_ago
    else
      without_candles += 1
    end
  end

  stats = {
    total_instruments: total,
    with_candles: with_candles,
    without_candles: without_candles,
    coverage_percentage: (with_candles.to_f / total * 100).round(2),
  }

  if days_ago_list.any?
    stats.merge!(
      oldest_days_ago: days_ago_list.max,
      newest_days_ago: days_ago_list.min,
      avg_days_ago: (days_ago_list.sum.to_f / days_ago_list.size).round(2),
      median_days_ago: days_ago_list.sort[days_ago_list.size / 2],
    )
  end

  puts "\n📊 #{timeframe} Candle Summary Statistics:"
  puts "=" * 60
  puts "   Total instruments: #{stats[:total_instruments]}"
  puts "   With candles: #{stats[:with_candles]} (#{stats[:coverage_percentage]}%)"
  puts "   Without candles: #{stats[:without_candles]}"
  if days_ago_list.any?
    puts "   Oldest candle: #{stats[:oldest_days_ago]} days ago"
    puts "   Newest candle: #{stats[:newest_days_ago]} days ago"
    puts "   Average age: #{stats[:avg_days_ago]} days"
    puts "   Median age: #{stats[:median_days_ago]} days"
  end

  stats
end

puts "\n✅ Candle finder scripts loaded!"
puts "\nAvailable functions:"
puts "  • find_latest_candle('RELIANCE', timeframe: '1D')"
puts "  • find_latest_candle_by_id(1, timeframe: '1D')"
puts "  • find_latest_candle_all_timeframes('TCS')"
puts "  • find_latest_candles_bulk(['RELIANCE', 'TCS', 'INFY'], timeframe: '1D')"
puts "  • find_stalest_candles(timeframe: '1D', limit: 10)"
puts "  • find_freshest_candles(timeframe: '1D', limit: 10)"
puts "  • candle_summary_stats(timeframe: '1D')"
puts "\n"
