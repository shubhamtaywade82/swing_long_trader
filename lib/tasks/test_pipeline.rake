# frozen_string_literal: true

namespace :test do
  namespace :pipeline do
    desc "Complete pipeline test: Universe → Instruments → Candles → Indicators → Screeners"
    task all: :environment do
      puts "\n" + "=" * 80
      puts "🚀 COMPLETE PIPELINE TEST"
      puts "=" * 80
      puts ""

      # Step 1: Universe
      puts "📋 STEP 1: Universe Build"
      puts "-" * 80
      Rake::Task["universe:build"].invoke
      Rake::Task["universe:stats"].invoke
      puts ""

      # Step 2: Instruments
      puts "📋 STEP 2: Import Instruments"
      puts "-" * 80
      Rake::Task["instruments:import"].invoke
      Rake::Task["universe:validate"].invoke
      puts ""

      # Step 3: Candles
      puts "📋 STEP 3: Ingest Candles"
      puts "-" * 80
      puts "Ingesting daily candles (30 days for testing)..."
      Rake::Task["candles:daily:ingest"].invoke(30)
      puts ""
      puts "Ingesting weekly candles (12 weeks for testing)..."
      Rake::Task["candles:weekly:ingest"].invoke(12)
      Rake::Task["candles:stats"].invoke
      puts ""

      # Step 4: Indicators
      puts "📋 STEP 4: Test Indicators"
      puts "-" * 80
      Rake::Task["indicators:test"].invoke
      puts ""

      # Step 5: Swing Screener
      puts "📋 STEP 5: Test Swing Screener"
      puts "-" * 80
      Rake::Task["screener:swing"].invoke
      puts ""

      # Step 6: Long-Term Screener
      puts "📋 STEP 6: Test Long-Term Screener"
      puts "-" * 80
      Rake::Task["screener:longterm"].invoke
      puts ""

      puts "=" * 80
      puts "✅ PIPELINE TEST COMPLETED"
      puts "=" * 80
    end

    desc "Step 1: Build universe from CSV files"
    task universe: :environment do
      puts "\n📋 Building Universe..."
      Rake::Task["universe:build"].invoke
      Rake::Task["universe:stats"].invoke
    end

    desc "Step 2: Import instruments from DhanHQ"
    task instruments: :environment do
      puts "\n📋 Importing Instruments..."
      Rake::Task["instruments:import"].invoke
      Rake::Task["universe:validate"].invoke
    end

    desc "Step 3: Ingest historical candles"
    task candles: :environment do
      puts "\n📋 Ingesting Candles..."
      days_back = ENV["DAYS_BACK"]&.to_i || 30
      weeks_back = ENV["WEEKS_BACK"]&.to_i || 12

      puts "Ingesting daily candles (#{days_back} days)..."
      Rake::Task["candles:daily:ingest"].invoke(days_back)
      puts ""
      puts "Ingesting weekly candles (#{weeks_back} weeks)..."
      Rake::Task["candles:weekly:ingest"].invoke(weeks_back)
      puts ""
      Rake::Task["candles:stats"].invoke
    end

    desc "Step 4: Test all indicators"
    task indicators: :environment do
      puts "\n📋 Testing Indicators..."
      Rake::Task["indicators:test"].invoke
    end

    desc "Step 5: Test swing screener"
    task swing: :environment do
      puts "\n📋 Testing Swing Screener..."
      Rake::Task["screener:swing"].invoke
    end

    desc "Step 6: Test long-term screener"
    task longterm: :environment do
      puts "\n📋 Testing Long-Term Screener..."
      Rake::Task["screener:longterm"].invoke
    end
  end
end

