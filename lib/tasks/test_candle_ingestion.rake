# frozen_string_literal: true

namespace :test do
  namespace :candles do
    desc "Test daily candle ingestion in Rails console"
    task daily: :environment do
      puts "\n=== Testing Daily Candle Ingestion ===\n\n"

      # Get a sample instrument
      instrument = Instrument.where(segment: "equity").where.not(security_id: nil).first
      unless instrument
        puts "❌ No equity instruments found. Please import instruments first."
        exit 1
      end

      puts "📊 Testing with instrument: #{instrument.symbol_name} (#{instrument.security_id})"
      puts "   Current candles in DB: #{CandleSeriesRecord.where(instrument: instrument, timeframe: '1D').count}\n"

      # Test daily ingestor
      puts "🔄 Running DailyIngestor with 30 days back..."
      result = Candles::DailyIngestor.call(
        instruments: Instrument.where(id: instrument.id),
        days_back: 30,
      )

      puts "\n✅ Result:"
      puts "   Success: #{result[:success]}"
      puts "   Processed: #{result[:processed]}"
      puts "   Failed: #{result[:failed]}"
      puts "   Total candles: #{result[:total_candles]}"
      puts "   Duration: #{result[:duration_minutes]&.round(2)} minutes"

      # Check candles in DB
      candle_count = CandleSeriesRecord.where(instrument: instrument, timeframe: "1D").count
      puts "\n📈 Candles in database: #{candle_count}"

      if candle_count > 0
        latest_candle = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: "1D")
        if latest_candle
          puts "   Latest candle date: #{latest_candle.timestamp.to_date}"
          puts "   Latest close: ₹#{latest_candle.close}"
        end
      end

      puts "\n✅ Daily ingestion test completed!\n"
    end

    desc "Test weekly candle ingestion in Rails console"
    task weekly: :environment do
      puts "\n=== Testing Weekly Candle Ingestion ===\n\n"

      # Get a sample instrument
      instrument = Instrument.where(segment: "equity").where.not(security_id: nil).first
      unless instrument
        puts "❌ No equity instruments found. Please import instruments first."
        exit 1
      end

      # Ensure we have daily candles first
      daily_count = CandleSeriesRecord.where(instrument: instrument, timeframe: "1D").count
      if daily_count < 7
        puts "⚠️  Not enough daily candles (#{daily_count}). Fetching daily candles first..."
        Candles::DailyIngestor.call(
          instruments: Instrument.where(id: instrument.id),
          days_back: 30,
        )
        daily_count = CandleSeriesRecord.where(instrument: instrument, timeframe: "1D").count
      end

      puts "📊 Testing with instrument: #{instrument.symbol_name} (#{instrument.security_id})"
      puts "   Daily candles available: #{daily_count}"
      puts "   Current weekly candles in DB: #{CandleSeriesRecord.where(instrument: instrument,
                                                                        timeframe: '1W').count}\n"

      # Test weekly ingestor
      puts "🔄 Running WeeklyIngestor with 4 weeks back..."
      result = Candles::WeeklyIngestor.call(
        instruments: Instrument.where(id: instrument.id),
        weeks_back: 4,
      )

      puts "\n✅ Result:"
      puts "   Success: #{result[:success]}"
      puts "   Processed: #{result[:processed]}"
      puts "   Failed: #{result[:failed]}"
      puts "   Total candles: #{result[:total_candles]}"
      puts "   Duration: #{result[:duration_minutes]&.round(2)} minutes"

      # Check candles in DB
      weekly_count = CandleSeriesRecord.where(instrument: instrument, timeframe: "1W").count
      puts "\n📈 Weekly candles in database: #{weekly_count}"

      if weekly_count > 0
        latest_weekly = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: "1W")
        if latest_weekly
          puts "   Latest weekly candle date: #{latest_weekly.timestamp.to_date}"
          puts "   Latest close: ₹#{latest_weekly.close}"
        end
      end

      puts "\n✅ Weekly ingestion test completed!\n"
    end

    desc "Test candle freshness checker"
    task freshness: :environment do
      puts "\n=== Testing Candle Freshness Checker ===\n\n"

      # Test daily freshness
      puts "🔄 Checking daily candle freshness..."
      daily_result = Candles::FreshnessChecker.ensure_fresh(
        timeframe: "1D",
        auto_ingest: false, # Don't auto-ingest in test
      )

      puts "\n📊 Daily Candles:"
      puts "   Fresh: #{daily_result[:fresh]}"
      puts "   Fresh count: #{daily_result[:fresh_count]}/#{daily_result[:total_count]}"
      puts "   Freshness percentage: #{daily_result[:freshness_percentage]&.round(1)}%"
      puts "   Cutoff date: #{daily_result[:cutoff_date]}"
      puts "   Cutoff trading days ago: #{daily_result[:cutoff_trading_days_ago]}"

      # Diagnostic: Check how many instruments have candles at all
      instruments_with_candles = Instrument.where(segment: %w[equity index])
                                           .joins("INNER JOIN candle_series ON candle_series.instrument_id = instruments.id")
                                           .where("candle_series.timeframe = ?", "1D")
                                           .distinct
                                           .count
      puts "   Instruments with candles: #{instruments_with_candles}/#{daily_result[:total_count]}"

      # Show sample of latest candle dates
      if instruments_with_candles.positive?
        sample_instruments = Instrument.where(segment: %w[equity index])
                                       .joins("INNER JOIN candle_series ON candle_series.instrument_id = instruments.id")
                                       .where("candle_series.timeframe = ?", "1D")
                                       .distinct
                                       .limit(5)
        puts "   Sample latest candle dates:"
        sample_instruments.each do |instrument|
          latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: "1D")
          next unless latest

          is_fresh = latest.timestamp.to_date >= daily_result[:cutoff_date]
          status = is_fresh ? "✅" : "❌"
          days_ago = (Time.zone.today - latest.timestamp.to_date).to_i
          puts "     #{status} #{instrument.symbol_name}: #{latest.timestamp.to_date} " \
               "(#{days_ago} days ago)"
        end
      end

      # Test weekly freshness
      puts "\n🔄 Checking weekly candle freshness..."
      weekly_result = Candles::FreshnessChecker.ensure_fresh(
        timeframe: "1W",
        auto_ingest: false, # Don't auto-ingest in test
      )

      puts "\n📊 Weekly Candles:"
      puts "   Fresh: #{weekly_result[:fresh]}"
      puts "   Fresh count: #{weekly_result[:fresh_count]}/#{weekly_result[:total_count]}"
      puts "   Freshness percentage: #{weekly_result[:freshness_percentage]&.round(1)}%"
      puts "   Cutoff date: #{weekly_result[:cutoff_date]}"
      puts "   Cutoff trading days ago: #{weekly_result[:cutoff_trading_days_ago]}"

      # Diagnostic: Check how many instruments have candles at all
      instruments_with_weekly = Instrument.where(segment: %w[equity index])
                                          .joins("INNER JOIN candle_series ON candle_series.instrument_id = instruments.id")
                                          .where("candle_series.timeframe = ?", "1W")
                                          .distinct
                                          .count
      puts "   Instruments with candles: #{instruments_with_weekly}/#{weekly_result[:total_count]}"

      # Show sample of latest candle dates
      if instruments_with_weekly.positive?
        sample_instruments = Instrument.where(segment: %w[equity index])
                                       .joins("INNER JOIN candle_series ON candle_series.instrument_id = instruments.id")
                                       .where("candle_series.timeframe = ?", "1W")
                                       .distinct
                                       .limit(5)
        puts "   Sample latest candle dates:"
        sample_instruments.each do |instrument|
          latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: "1W")
          next unless latest

          is_fresh = latest.timestamp.to_date >= weekly_result[:cutoff_date]
          status = is_fresh ? "✅" : "❌"
          days_ago = (Time.zone.today - latest.timestamp.to_date).to_i
          puts "     #{status} #{instrument.symbol_name}: #{latest.timestamp.to_date} " \
               "(#{days_ago} days ago)"
        end
      end

      # Summary and recommendations
      puts "\n📋 Summary:"
      if daily_result[:freshness_percentage] < 80.0 || weekly_result[:freshness_percentage] < 80.0
        puts "   ⚠️  Candles are stale and need to be updated."
        puts "   💡 To update candles, run:"
        puts "      rails candles:daily:ingest[365]   # For daily candles (365 days back)"
        puts "      rails candles:weekly:ingest[52]  # For weekly candles (52 weeks back)"
        puts "      rails candles:check_freshness     # Check and auto-ingest if stale"
      else
        puts "   ✅ Candles are fresh!"
      end

      puts "\n✅ Freshness check completed!\n"
    end

    desc "Test all candle ingestion services"
    task all: :environment do
      Rake::Task["test:candles:daily"].invoke
      Rake::Task["test:candles:weekly"].invoke
      Rake::Task["test:candles:freshness"].invoke
    end
  end
end
