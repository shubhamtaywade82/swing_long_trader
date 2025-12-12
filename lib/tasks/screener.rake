# frozen_string_literal: true

namespace :screener do
  desc "Run swing screener to find swing trading candidates"
  task swing: :environment do
    puts "\n🔍 Running Swing Screener..."
    puts "=" * 60

    start_time = Time.current
    result = Screeners::SwingScreener.call

    if result.is_a?(Array)
      candidates = result
    elsif result.is_a?(Hash) && result[:candidates]
      candidates = result[:candidates]
    else
      candidates = []
    end

    duration = Time.current - start_time

    puts "\n✅ Swing Screener completed in #{(duration / 60).round(1)} minutes"
    puts "   Found #{candidates.size} candidates"
    puts ""

    if candidates.any?
      puts "📊 Top Candidates:"
      puts "-" * 90
      candidates.first(20).each_with_index do |candidate, index|
        symbol = candidate[:symbol] || candidate[:symbol_name] || "N/A"
        score = candidate[:score] || 0

        # Extract direction from indicators.supertrend or metadata
        direction = candidate.dig(:indicators, :supertrend, :direction) ||
                   candidate.dig(:metadata, :trend_alignment)&.first ||
                   candidate[:direction] ||
                   "N/A"
        direction = direction.to_s.upcase if direction.is_a?(Symbol)

        # Extract RSI for additional context
        rsi = candidate.dig(:indicators, :rsi)
        rsi_str = rsi ? "RSI: #{rsi.round(1)}" : ""

        # Extract trend alignment
        trend_alignment = candidate.dig(:metadata, :trend_alignment)
        trend_str = trend_alignment&.any? ? trend_alignment.join(", ") : ""

        puts "#{(index + 1).to_s.rjust(3)}. #{symbol.ljust(35)} | " \
             "Score: #{score.round(1).to_s.rjust(5)} | " \
             "Direction: #{direction.to_s.ljust(8)} | " \
             "#{rsi_str}"
        puts "     Trend: #{trend_str}" if trend_str.present?
      end
      puts "-" * 90
      puts ""
      puts "💡 Tip: Use 'rails console' to access full candidate data:"
      puts "   result = Screeners::SwingScreener.call(limit: 50)"
      puts "   result.first(5)"
    else
      puts "⚠️  No candidates found"
      puts "   This is normal if market conditions don't meet screening criteria"
      puts "   Try adjusting screening parameters in config/algo_config.yml"
    end

    puts ""
  end

  desc "Run long-term screener to find long-term trading candidates"
  task longterm: :environment do
    puts "\n🔍 Running Long-Term Screener..."
    puts "=" * 60

    start_time = Time.current
    result = Screeners::LongtermScreener.call

    if result.is_a?(Array)
      candidates = result
    elsif result.is_a?(Hash) && result[:candidates]
      candidates = result[:candidates]
    else
      candidates = []
    end

    duration = Time.current - start_time

    puts "\n✅ Long-Term Screener completed in #{(duration / 60).round(1)} minutes"
    puts "   Found #{candidates.size} candidates"
    puts ""

    if candidates.any?
      puts "📊 Top Candidates:"
      puts "-" * 90
      candidates.first(20).each_with_index do |candidate, index|
        symbol = candidate[:symbol] || candidate[:symbol_name] || "N/A"
        score = candidate[:score] || 0

        # Extract direction from indicators.supertrend or metadata
        direction = candidate.dig(:indicators, :supertrend, :direction) ||
                   candidate.dig(:metadata, :trend_alignment)&.first ||
                   candidate[:direction] ||
                   "N/A"
        direction = direction.to_s.upcase if direction.is_a?(Symbol)

        # Extract RSI for additional context
        rsi = candidate.dig(:indicators, :rsi)
        rsi_str = rsi ? "RSI: #{rsi.round(1)}" : ""

        # Extract trend alignment
        trend_alignment = candidate.dig(:metadata, :trend_alignment)
        trend_str = trend_alignment&.any? ? trend_alignment.join(", ") : ""

        puts "#{(index + 1).to_s.rjust(3)}. #{symbol.ljust(35)} | " \
             "Score: #{score.round(1).to_s.rjust(5)} | " \
             "Direction: #{direction.to_s.ljust(8)} | " \
             "#{rsi_str}"
        puts "     Trend: #{trend_str}" if trend_str.present?
      end
      puts "-" * 90
      puts ""
      puts "💡 Tip: Use 'rails console' to access full candidate data:"
      puts "   result = Screeners::LongtermScreener.call(limit: 20)"
      puts "   result.first(5)"
    else
      puts "⚠️  No candidates found"
      puts "   This is normal if market conditions don't meet screening criteria"
      puts "   Try adjusting screening parameters in config/algo_config.yml"
    end

    puts ""
  end

  desc "Run both screeners and show summary"
  task all: :environment do
    puts "\n🔍 Running All Screeners..."
    puts "=" * 60
    puts ""

    # Run swing screener
    puts "1️⃣  Swing Screener:"
    Rake::Task["screener:swing"].invoke

    puts "\n" + "=" * 60 + "\n"

    # Run long-term screener
    puts "2️⃣  Long-Term Screener:"
    Rake::Task["screener:longterm"].invoke

    puts "\n✅ All screeners completed!"
  end

  desc "Show screener statistics"
  task stats: :environment do
    puts "\n📊 Screener Statistics"
    puts "=" * 60

    # Check universe size
    if IndexConstituent.exists?
      universe_size = IndexConstituent.distinct.count(:symbol)
      puts "Universe size: #{universe_size} unique symbols"
    else
      puts "⚠️  No universe found - run 'rails universe:build' first"
    end

    # Check instruments with candles
    instruments_with_daily = Instrument.joins(:candle_series_records)
                                      .where(candle_series_records: { timeframe: "1D" })
                                      .distinct
                                      .count
    instruments_with_weekly = Instrument.joins(:candle_series_records)
                                        .where(candle_series_records: { timeframe: "1W" })
                                        .distinct
                                        .count

    puts "Instruments with daily candles: #{instruments_with_daily}"
    puts "Instruments with weekly candles: #{instruments_with_weekly}"

    # Check readiness
    puts ""
    if instruments_with_daily >= 50
      puts "✅ Ready for swing screening (#{instruments_with_daily} instruments)"
    else
      puts "⚠️  Low instrument count for swing screening"
    end

    if instruments_with_weekly >= 20
      puts "✅ Ready for long-term screening (#{instruments_with_weekly} instruments)"
    else
      puts "⚠️  Low instrument count for long-term screening"
    end

    puts ""
  end
end

