# frozen_string_literal: true

namespace :production do
  desc "Verify system is ready for production deployment"
  task ready: :environment do
    puts "\n=== 🚀 PRODUCTION READINESS CHECK ===\n\n"

    all_checks_passed = true

    # 1. Environment Variables
    puts "1. Checking environment variables..."
    required_vars = %w[DATABASE_URL DHANHQ_CLIENT_ID DHANHQ_ACCESS_TOKEN]
    missing_vars = required_vars.reject { |var| ENV[var].present? }

    if missing_vars.empty?
      puts "   ✅ All required environment variables set"
    else
      puts "   ❌ Missing environment variables: #{missing_vars.join(', ')}"
      all_checks_passed = false
    end

    # 2. Database Connection
    puts "\n2. Checking database connection..."
    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      puts "   ✅ Database connection successful"
    rescue StandardError => e
      puts "   ❌ Database connection failed: #{e.message}"
      all_checks_passed = false
    end

    # 3. Database Migrations
    puts "\n3. Checking database migrations..."
    begin
      pending = ActiveRecord::Migration.check_pending!
      if pending.nil?
        puts "   ✅ All migrations applied"
      else
        puts "   ⚠️  Pending migrations detected"
        all_checks_passed = false
      end
    rescue StandardError => e
      puts "   ⚠️  Could not check migrations: #{e.message}"
    end

    # 4. Instruments Imported
    puts "\n4. Checking instrument import..."
    instrument_count = Instrument.count
    if instrument_count.positive?
      puts "   ✅ Instruments imported: #{instrument_count}"
    else
      puts "   ⚠️  No instruments imported - run 'rails instruments:import'"
    end

    # 5. Candle Data
    puts "\n5. Checking candle data..."
    daily_count = CandleSeriesRecord.where(timeframe: "1D").count
    weekly_count = CandleSeriesRecord.where(timeframe: "1W").count

    if daily_count.positive?
      puts "   ✅ Daily candles: #{daily_count}"
    else
      puts "   ⚠️  No daily candles - run 'rails runner \"Candles::DailyIngestor.call\"'"
    end

    if weekly_count.positive?
      puts "   ✅ Weekly candles: #{weekly_count}"
    else
      puts "   ⚠️  No weekly candles - run 'rails runner \"Candles::WeeklyIngestor.call\"'"
    end

    # 6. SolidQueue Configuration
    puts "\n6. Checking SolidQueue configuration..."
    if defined?(SolidQueue)
      begin
        job_count = SolidQueue::Job.count
        puts "   ✅ SolidQueue configured (jobs in queue: #{job_count})"
      rescue StandardError => e
        puts "   ⚠️  SolidQueue not accessible: #{e.message}"
      end
    else
      puts "   ⚠️  SolidQueue not loaded"
    end

    # 7. Configuration Files
    puts "\n7. Checking configuration files..."
    config_files = {
      "config/algo.yml" => "Trading configuration",
      "config/recurring.yml" => "Job schedules",
      "config/universe/master_universe.yml" => "Universe whitelist",
    }

    config_files.each do |file, description|
      if Rails.root.join(file).exist?
        puts "   ✅ #{description}: #{file}"
      else
        puts "   ⚠️  Missing: #{file} (#{description})"
        puts "      Run 'rails universe:build' to create" if file == "config/universe/master_universe.yml"
      end
    end

    # 8. API Credentials
    puts "\n8. Checking API credentials..."
    dhan_configured = ENV["DHANHQ_CLIENT_ID"].present? && ENV["DHANHQ_ACCESS_TOKEN"].present?
    telegram_configured = ENV["TELEGRAM_BOT_TOKEN"].present? && ENV["TELEGRAM_CHAT_ID"].present?
    openai_configured = ENV["OPENAI_API_KEY"].present?

    puts "   DhanHQ: #{dhan_configured ? '✅' : '❌'} (Required)"
    puts "   Telegram: #{telegram_configured ? '✅' : '⚠️ '} (Optional)"
    puts "   OpenAI: #{openai_configured ? '✅' : '⚠️ '} (Optional)"

    all_checks_passed = false unless dhan_configured

    # 9. Test Infrastructure
    puts "\n9. Checking test infrastructure..."
    if Rails.root.join("spec").exist?
      spec_count = Rails.root.glob("spec/**/*_spec.rb").count
      puts "   ✅ RSpec configured (#{spec_count} spec files)"
    else
      puts "   ⚠️  RSpec not configured"
    end

    # 10. Risk Items
    puts "\n10. Checking risk items..."
    puts "   Run 'rails verify:risks' for detailed risk verification"

    # Summary
    puts "\n=== 📊 SUMMARY ===\n"
    if all_checks_passed
      puts "✅ System appears ready for production"
      puts "\nNext steps:"
      puts "  1. Run 'rails verify:risks' for risk verification"
      puts "  2. Run 'rails hardening:check' for security checks"
      puts "  3. Review production checklist: docs/PRODUCTION_CHECKLIST.md"
      puts "  4. Enable dry-run mode for first week"
      puts "  5. Monitor closely during initial deployment"
    else
      puts "⚠️  Some checks failed - review above and fix issues"
      puts "\nCommon fixes:"
      puts "  - Set missing environment variables"
      puts "  - Run 'rails db:migrate' if migrations pending"
      puts "  - Run 'rails instruments:import' if no instruments"
      puts "  - Run 'rails universe:build' if universe missing"
    end
    puts "\n"
  end

  desc "Show production deployment checklist"
  task checklist: :environment do
    puts "\n=== 📋 PRODUCTION DEPLOYMENT CHECKLIST ===\n\n"

    checklist = [
      { category: "Pre-Deployment", items: [
        "All tests passing (bundle exec rspec)",
        "No RuboCop violations (bundle exec rubocop)",
        "No Brakeman security issues (bundle exec brakeman)",
        "Code coverage > 80%",
        "All environment variables configured",
        "Database migrations applied",
        "Instruments imported",
        "Historical candles ingested",
        "Universe configured",
      ] },
      { category: "Configuration", items: [
        "config/algo.yml configured for production",
        "config/recurring.yml schedules verified",
        "Dry-run mode enabled (for first week)",
        "Telegram notifications configured",
        "OpenAI API key configured (if using AI ranking)",
      ] },
      { category: "Testing", items: [
        "Run comprehensive backtest (3+ months)",
        "Validate backtest results",
        "Test screener pipeline",
        "Test signal generation",
        "Test Telegram notifications",
        "Test job scheduling",
      ] },
      { category: "Monitoring", items: [
        "Metrics tracking enabled",
        "Health checks configured",
        "Alert thresholds set",
        "Logging configured",
        "Error tracking enabled",
      ] },
      { category: "Deployment", items: [
        "Deploy application server",
        "Start SolidQueue workers",
        "Verify job execution",
        "Monitor first day closely",
        "Review metrics daily",
      ] },
      { category: "Post-Deployment", items: [
        "Monitor for first week in dry-run mode",
        "Review generated signals",
        "Validate order placement (dry-run)",
        "Enable manual approval for first 30 trades",
        "Gradually enable auto-execution",
      ] },
    ]

    checklist.each do |section|
      puts "## #{section[:category]}"
      section[:items].each do |item|
        puts "  [ ] #{item}"
      end
      puts
    end

    puts "For detailed instructions, see:"
    puts "  - docs/DEPLOYMENT_QUICKSTART.md"
    puts "  - docs/PRODUCTION_CHECKLIST.md"
    puts "  - docs/runbook.md"
    puts "\n"
  end
end
