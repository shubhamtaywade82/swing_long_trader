# frozen_string_literal: true

namespace :candles do
  namespace :daily do
    desc "Clear all daily candles (use before re-ingesting with fixed code)"
    task clear: :environment do
      count = CandleSeriesRecord.where(timeframe: "1D").count
      if count.positive?
        print "⚠️  About to delete #{count} daily candles. Continue? (y/N): "
        response = $stdin.gets.chomp.downcase
        if response == "y"
          CandleSeriesRecord.where(timeframe: "1D").delete_all
          puts "✅ Deleted #{count} daily candles"
        else
          puts "❌ Cancelled"
        end
      else
        puts "ℹ️  No daily candles to delete"
      end
    end

    desc "Ingest daily candles (with fixed timestamp parsing)"
    task :ingest, [:days_back] => :environment do |_t, args|
      days_back = args[:days_back]&.to_i || 365
      puts "📊 Starting daily candle ingestion (#{days_back} days back)..."
      result = Candles::DailyIngestor.call(days_back: days_back)
      puts "\n✅ Ingestion completed!"
      puts "   Processed: #{result[:processed]}"
      puts "   Success: #{result[:success]}"
      puts "   Failed: #{result[:failed]}"
      puts "   Total candles: #{result[:total_candles]}"
    end
  end

  namespace :weekly do
    desc "Clear all weekly candles"
    task clear: :environment do
      count = CandleSeriesRecord.where(timeframe: "1W").count
      if count.positive?
        print "⚠️  About to delete #{count} weekly candles. Continue? (y/N): "
        response = $stdin.gets.chomp.downcase
        if response == "y"
          CandleSeriesRecord.where(timeframe: "1W").delete_all
          puts "✅ Deleted #{count} weekly candles"
        else
          puts "❌ Cancelled"
        end
      else
        puts "ℹ️  No weekly candles to delete"
      end
    end

    desc "Ingest weekly candles (aggregates from daily)"
    task :ingest, [:weeks_back] => :environment do |_t, args|
      weeks_back = args[:weeks_back]&.to_i || 52
      puts "📊 Starting weekly candle ingestion (#{weeks_back} weeks back)..."
      result = Candles::WeeklyIngestor.call(weeks_back: weeks_back)
      puts "\n✅ Ingestion completed!"
      puts "   Processed: #{result[:processed]}"
      puts "   Success: #{result[:success]}"
      puts "   Failed: #{result[:failed]}"
      puts "   Total candles: #{result[:total_candles]}"
    end
  end

  desc "Check candle freshness and trigger ingestion if stale"
  task check_freshness: :environment do
    puts "\n🔍 Checking candle freshness..."
    puts "=" * 60

    %w[1D 1W].each do |timeframe|
      puts "\n📊 Checking #{timeframe} candles..."
      result = Candles::FreshnessChecker.ensure_fresh(
        timeframe: timeframe,
        auto_ingest: true,
      )

      if result[:fresh]
        puts "✅ #{timeframe} candles are fresh: #{result[:fresh_count]}/#{result[:total_count]} instruments " \
             "(#{result[:freshness_percentage].round(1)}%)"
      else
        puts "⚠️  #{timeframe} candles are stale: #{result[:fresh_count]}/#{result[:total_count]} instruments " \
             "(#{result[:freshness_percentage].round(1)}%)"
        if result[:ingested]
          puts "   ✅ Ingestion triggered: #{result.dig(:ingestion_result, :total_candles) || 0} candles processed"
        else
          puts "   ⚠️  Auto-ingestion disabled or failed"
        end
      end
    end

    puts "\n" + "=" * 60
    puts "✅ Freshness check complete!"
  end

  desc "Show candle statistics"
  task stats: :environment do
    daily_count = CandleSeriesRecord.where(timeframe: "1D").count
    weekly_count = CandleSeriesRecord.where(timeframe: "1W").count
    daily_instruments = CandleSeriesRecord.where(timeframe: "1D").distinct.count(:instrument_id)
    weekly_instruments = CandleSeriesRecord.where(timeframe: "1W").distinct.count(:instrument_id)
    unique_dates = CandleSeriesRecord.where(timeframe: "1D").distinct.pluck("DATE(timestamp)").size

    puts "\n📊 Candle Statistics"
    puts "=" * 60
    puts "Daily Candles:"
    puts "  Total: #{daily_count}"
    puts "  Instruments: #{daily_instruments}"
    puts "  Unique dates: #{unique_dates}"
    if daily_instruments.positive?
      avg_daily = (daily_count.to_f / daily_instruments).round(1)
      puts "  Average per instrument: #{avg_daily}"
    end
    puts ""
    puts "Weekly Candles:"
    puts "  Total: #{weekly_count}"
    puts "  Instruments: #{weekly_instruments}"
    if weekly_instruments.positive?
      avg_weekly = (weekly_count.to_f / weekly_instruments).round(1)
      puts "  Average per instrument: #{avg_weekly}"
    end
    puts ""

    if unique_dates == 1 && daily_count > 0
      puts "⚠️  WARNING: All daily candles have the same date!"
      puts "   This indicates old buggy data. Clear and re-ingest:"
      puts "   rails candles:daily:clear"
      puts "   rails candles:daily:ingest[800]"
    end
  end
end
