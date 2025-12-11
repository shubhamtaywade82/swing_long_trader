# frozen_string_literal: true

namespace :verification do
  desc 'Run complete verification workflow (guides through all manual steps)'
  task workflow: :environment do
    puts "\n=== 🔍 COMPLETE VERIFICATION WORKFLOW ===\n\n"
    puts "This workflow will guide you through all verification steps.\n\n"

    all_passed = true

    # Phase 1: System Completeness
    puts "📋 PHASE 1: System Completeness Check"
    puts "-" * 50
    system("rails verify:complete > /tmp/verify_complete.txt 2>&1")
    if $CHILD_STATUS.success?
      puts "✅ System completeness check passed\n\n"
    else
      puts "❌ System completeness check failed - review output above\n\n"
      all_passed = false
    end

    # Phase 2: Risk Verification
    puts "📋 PHASE 2: Risk Verification"
    puts "-" * 50
    system("rails verify:risks > /tmp/verify_risks.txt 2>&1")
    if $CHILD_STATUS.success?
      puts "✅ Risk verification passed\n\n"
    else
      puts "❌ Risk verification failed - review output above\n\n"
      all_passed = false
    end

    # Phase 3: Production Readiness
    puts "📋 PHASE 3: Production Readiness Check"
    puts "-" * 50
    system("rails production:ready > /tmp/production_ready.txt 2>&1")
    if $CHILD_STATUS.success?
      puts "✅ Production readiness check passed\n\n"
    else
      puts "⚠️  Production readiness check has warnings - review output above\n\n"
    end

    # Phase 4: Database Status
    puts "📋 PHASE 4: Database Status"
    puts "-" * 50
    instrument_count = Instrument.count rescue 0
    candle_count = CandleSeriesRecord.count rescue 0
    order_count = Order.count rescue 0

    puts "   Instruments: #{instrument_count}"
    puts "   Candle Series: #{candle_count}"
    puts "   Orders: #{order_count}"

    if instrument_count.zero?
      puts "   ⚠️  No instruments found - run 'rails instruments:import'\n\n"
    elsif instrument_count < 100
      puts "   ⚠️  Low instrument count - verify import completed\n\n"
    else
      puts "   ✅ Instruments present\n\n"
    end

    # Phase 5: Configuration Check
    puts "📋 PHASE 5: Configuration Check"
    puts "-" * 50
    config_checks = {
      'DhanHQ Client ID' => ENV['DHANHQ_CLIENT_ID'].present?,
      'DhanHQ Access Token' => ENV['DHANHQ_ACCESS_TOKEN'].present?,
      'Telegram Bot Token' => ENV['TELEGRAM_BOT_TOKEN'].present?,
      'Telegram Chat ID' => ENV['TELEGRAM_CHAT_ID'].present?,
      'OpenAI API Key' => ENV['OPENAI_API_KEY'].present?
    }

    config_checks.each do |name, present|
      if present
        puts "   ✅ #{name}: Configured"
      else
        puts "   ⚠️  #{name}: Not configured (optional)"
      end
    end
    puts "\n"

    # Phase 6: Manual Steps Checklist
    puts "📋 PHASE 6: Manual Verification Steps"
    puts "-" * 50
    puts "The following steps require manual execution:\n\n"

    manual_steps = [
      {
        name: 'Run Instrument Import',
        command: 'rails instruments:import',
        description: 'Import instruments from DhanHQ (requires credentials)',
        check: -> { Instrument.count > 0 }
      },
      {
        name: 'Build Universe',
        command: 'rails universe:build',
        description: 'Build master universe from CSV files',
        check: -> { File.exist?(Rails.root.join('config/universe/master_universe.yml')) }
      },
      {
        name: 'Run RSpec Tests',
        command: 'bundle exec rspec',
        description: 'Verify all tests pass',
        check: -> { File.exist?(Rails.root.join('coverage/.last_run.json')) }
      },
      {
        name: 'Run RuboCop',
        command: 'bundle exec rubocop',
        description: 'Check code style',
        check: -> { false } # Always requires manual run
      },
      {
        name: 'Run Brakeman',
        command: 'bundle exec brakeman',
        description: 'Check security vulnerabilities',
        check: -> { false } # Always requires manual run
      },
      {
        name: 'Run Risk Control Tests',
        command: 'rails test:risk:all',
        description: 'Test idempotency, exposure limits, circuit breakers',
        check: -> { false } # Always requires manual run
      }
    ]

    manual_steps.each_with_index do |step, index|
      status = step[:check].call ? '✅' : '⏳'
      puts "   #{index + 1}. #{status} #{step[:name]}"
      puts "      Command: #{step[:command]}"
      puts "      #{step[:description]}\n"
    end

    # Summary
    puts "\n=== 📊 VERIFICATION SUMMARY ===\n"
    if all_passed && instrument_count > 0
      puts "✅ Core system checks passed"
      puts "\nNext steps:"
      puts "  1. Complete manual verification steps above"
      puts "  2. Run comprehensive backtest"
      puts "  3. Validate backtest results"
      puts "  4. Test order execution in dry-run mode"
      puts "  5. Review production checklist: rails production:checklist"
    elsif all_passed
      puts "✅ System checks passed, but data import needed"
      puts "\nNext steps:"
      puts "  1. Run 'rails instruments:import' to import instruments"
      puts "  2. Run 'rails universe:build' to build universe"
      puts "  3. Complete remaining manual verification steps"
    else
      puts "⚠️  Some checks failed - review output above"
      puts "\nNext steps:"
      puts "  1. Fix any system completeness issues"
      puts "  2. Review risk verification output"
      puts "  3. Complete manual verification steps"
    end

    puts "\nFor detailed manual verification steps, see: docs/MANUAL_VERIFICATION_STEPS.md\n"
  end

  desc 'Validate backtest signals match live signals (helper for manual verification)'
  task validate_signals: :environment do
    puts "\n=== 🔍 BACKTEST SIGNAL VALIDATION ===\n\n"
    puts "This helper validates that backtest signals match live signals.\n\n"

    # Check if we have instruments
    if Instrument.count.zero?
      puts "❌ No instruments found. Run 'rails instruments:import' first.\n"
      exit 1
    end

    # Get a sample instrument
    instrument = Instrument.first
    puts "Testing with instrument: #{instrument.symbol_name}\n\n"

    # Load candles
    puts "Loading candles..."
    daily_series = instrument.load_daily_candles(limit: 100) rescue nil
    weekly_series = instrument.load_weekly_candles(limit: 52) rescue nil

    if daily_series.nil? || daily_series.empty?
      puts "❌ No daily candles found. Run candle ingestion first.\n"
      exit 1
    end

    if weekly_series.nil? || weekly_series.empty?
      puts "❌ No weekly candles found. Run candle ingestion first.\n"
      exit 1
    end

    puts "✅ Loaded #{daily_series.size} daily candles and #{weekly_series.size} weekly candles\n\n"

    # Generate live signal
    puts "Generating live signal..."
    live_result = Strategies::Swing::Engine.call(
      instrument: instrument,
      daily_series: daily_series,
      weekly_series: weekly_series
    )

    if live_result[:success] && live_result[:signal]
      live_signal = live_result[:signal]
      puts "✅ Live signal generated:\n"
      puts "   Direction: #{live_signal[:direction]}"
      puts "   Entry Price: #{live_signal[:entry_price]}"
      puts "   Quantity: #{live_signal[:qty]}"
      puts "   Stop Loss: #{live_signal[:stop_loss]}"
      puts "   Take Profit: #{live_signal[:take_profit]}"
      puts "   Confidence: #{live_signal[:confidence]}%\n\n"
    else
      puts "⚠️  No live signal generated (may be expected)\n\n"
    end

    # Run backtest for same period
    puts "Running backtest for comparison..."
    backtest_result = Backtesting::SwingBacktester.call(
      instrument: instrument,
      start_date: daily_series.first[:timestamp].to_date,
      end_date: daily_series.last[:timestamp].to_date,
      initial_capital: 100_000
    )

    if backtest_result[:success]
      puts "✅ Backtest completed:\n"
      puts "   Total Trades: #{backtest_result[:results][:total_trades]}"
      puts "   Win Rate: #{backtest_result[:results][:win_rate].round(2)}%"
      puts "   Total P&L: ₹#{backtest_result[:results][:total_pnl].round(2)}"
      puts "   Sharpe Ratio: #{backtest_result[:results][:sharpe_ratio].round(2)}\n\n"

      if backtest_result[:results][:positions].any?
        first_position = backtest_result[:results][:positions].first
        puts "First backtest position:\n"
        puts "   Entry: ₹#{first_position[:entry_price]}"
        puts "   Exit: ₹#{first_position[:exit_price]}"
        puts "   Direction: #{first_position[:direction]}"
        puts "   P&L: ₹#{first_position[:pnl].round(2)}\n\n"
      end
    else
      puts "⚠️  Backtest failed: #{backtest_result[:error]}\n\n"
    end

    puts "=== 📊 VALIDATION SUMMARY ===\n"
    puts "Compare the signals above to ensure they match.\n"
    puts "For detailed validation, see: docs/MANUAL_VERIFICATION_STEPS.md\n"
  end

  desc 'Quick health check (all automated checks)'
  task health: :environment do
    puts "\n=== 🏥 QUICK HEALTH CHECK ===\n\n"

    checks = {
      'Database Connection' => -> { ActiveRecord::Base.connection.active? },
      'Instruments Present' => -> { Instrument.count > 0 },
      'Candles Present' => -> { CandleSeriesRecord.count > 0 },
      'DhanHQ Config' => -> { ENV['DHANHQ_CLIENT_ID'].present? && ENV['DHANHQ_ACCESS_TOKEN'].present? },
      'Telegram Config' => -> { ENV['TELEGRAM_BOT_TOKEN'].present? && ENV['TELEGRAM_CHAT_ID'].present? },
      'OpenAI Config' => -> { ENV['OPENAI_API_KEY'].present? }
    }

    all_ok = true
    checks.each do |name, check|
      begin
        result = check.call
        status = result ? '✅' : '⚠️'
        puts "#{status} #{name}"
        all_ok = false unless result
      rescue StandardError => e
        puts "❌ #{name}: #{e.message}"
        all_ok = false
      end
    end

    puts "\n"
    if all_ok
      puts "✅ All health checks passed!\n"
    else
      puts "⚠️  Some health checks failed - review above\n"
    end
    puts "\n"
  end
end

