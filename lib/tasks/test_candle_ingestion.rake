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
        latest_candle = CandleSeriesRecord.where(instrument: instrument, timeframe: "1D")
                                          .order(timestamp: :desc).first
        puts "   Latest candle date: #{latest_candle.timestamp.to_date}"
        puts "   Latest close: ₹#{latest_candle.close}"
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
        latest_weekly = CandleSeriesRecord.where(instrument: instrument, timeframe: "1W")
                                          .order(timestamp: :desc).first
        puts "   Latest weekly candle date: #{latest_weekly.timestamp.to_date}"
        puts "   Latest close: ₹#{latest_weekly.close}"
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
