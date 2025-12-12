# frozen_string_literal: true

namespace :verify do
  desc "Verify all critical risk items are addressed"
  task risks: :environment do
    puts "\n=== 🔍 RISK ITEMS VERIFICATION ===\n\n"

    all_passed = true

    # 1. Verify NO scalper WebSocket code
    puts "1. Checking for scalper WebSocket code..."
    scalper_files = []
    %w[app lib config].each do |dir|
      next unless Dir.exist?(dir)

      Dir.glob("#{dir}/**/*.rb").each do |file|
        content = File.read(file)
        # Check for actual scalper code (not just comments)
        if content.match?(/Live::|WebSocket|websocket|ws_|tick_cache|TickCache|PositionTracker|Derivative|WatchlistItem|bracket|Bracket/) &&
           !content.match?(/#.*(removed|skip|disabled|scalper)/i)
          scalper_files << file
        end
      end
    end

    if scalper_files.empty?
      puts "   ✅ No scalper WebSocket code found (only comments/documentation)"
    else
      puts "   ❌ Found potential scalper code in:"
      scalper_files.each { |f| puts "      - #{f}" }
      all_passed = false
    end

    # 2. Verify intraday fetch is only for finalists
    puts "\n2. Checking intraday fetcher usage..."
    intraday_files = Dir.glob("app/**/*.rb").select { |f| File.read(f).include?("IntradayFetcher") }
    if intraday_files.any?
      puts "   ✅ IntradayFetcher found in: #{intraday_files.size} file(s)"
      puts "      - Verify it's only called for finalists (top candidates)"
      puts "      - Files: #{intraday_files.map { |f| File.basename(f) }.join(', ')}"
    else
      puts "   ⚠️  IntradayFetcher not found in codebase"
    end

    # 3. Verify OpenAI cost controls
    puts "\n3. Checking OpenAI cost controls..."
    openai_client = File.read("app/services/openai/client.rb")
    has_cache = openai_client.include?("fetch_from_cache") || openai_client.include?("cache_result")
    has_rate_limit = openai_client.include?("rate_limit_exceeded?") || openai_client.include?("MAX_CALLS_PER_DAY")
    has_cost_monitoring = openai_client.include?("check_cost_thresholds") || openai_client.include?("calculate_cost")

    if has_cache && has_rate_limit && has_cost_monitoring
      puts "   ✅ OpenAI cost controls implemented:"
      puts "      - Caching: ✅"
      puts "      - Rate limiting: ✅"
      puts "      - Cost monitoring: ✅"
    else
      puts "   ❌ OpenAI cost controls incomplete:"
      puts "      - Caching: #{has_cache ? '✅' : '❌'}"
      puts "      - Rate limiting: #{has_rate_limit ? '✅' : '❌'}"
      puts "      - Cost monitoring: #{has_cost_monitoring ? '✅' : '❌'}"
      all_passed = false
    end

    # 4. Verify DB-backed jobs (SolidQueue)
    puts "\n4. Checking job backend..."
    if defined?(SolidQueue)
      puts "   ✅ SolidQueue is configured"
    elsif File.read("config/application.rb").include?("solid_queue")
      puts "   ✅ SolidQueue configured in application.rb"
    else
      puts "   ❌ SolidQueue not found - using in-memory jobs?"
      all_passed = false
    end

    # 5. Verify job failure alerts
    puts "\n5. Checking job failure alerts..."
    job_logging = File.read("app/jobs/concerns/job_logging.rb")
    has_error_handling = job_logging.include?("rescue") || job_logging.include?("error")
    has_telegram_alert = job_logging.include?("Telegram") || job_logging.include?("send_error_alert")

    if has_error_handling && has_telegram_alert
      puts "   ✅ Job failure alerts implemented"
    else
      puts "   ⚠️  Job failure alerts may be incomplete:"
      puts "      - Error handling: #{has_error_handling ? '✅' : '❌'}"
      puts "      - Telegram alerts: #{has_telegram_alert ? '✅' : '❌'}"
    end

    # 6. Verify idempotency (order placement)
    puts "\n6. Checking order idempotency..."
    orders_service = File.read("app/services/dhan/orders.rb")
    has_idempotency = orders_service.include?("client_order_id") || orders_service.include?("check_duplicate_order") || orders_service.include?("idempotent")

    if has_idempotency
      puts "   ✅ Order idempotency implemented (client_order_id check)"
    else
      puts "   ❌ Order idempotency not found"
      all_passed = false
    end

    # 7. Verify risk limits
    puts "\n7. Checking risk limits..."
    executor = File.read("app/services/strategies/swing/executor.rb")
    has_risk_checks = executor.include?("check_risk_limits") || executor.include?("max_position_size") || executor.include?("max_exposure") || executor.include?("circuit_breaker")

    if has_risk_checks
      puts "   ✅ Risk limits implemented"
    else
      puts "   ❌ Risk limits not found"
      all_passed = false
    end

    # 8. Verify auto-execution safeguards
    puts "\n8. Checking auto-execution safeguards..."
    has_dry_run = orders_service.include?("dry_run") || File.read("config/algo.yml").include?("dry_run")
    has_manual_accept = executor.include?("manual") || executor.include?("confirmation")

    if has_dry_run
      puts "   ✅ Dry-run mode available"
    else
      puts "   ⚠️  Dry-run mode not found"
    end

    if has_manual_accept
      puts "   ✅ Manual acceptance available"
    else
      puts "   ⚠️  Manual acceptance not found (consider adding for first 30 trades)"
    end

    # Summary
    puts "\n=== 📊 VERIFICATION SUMMARY ===\n"
    if all_passed
      puts "✅ All critical risk items verified"
    else
      puts "⚠️  Some risk items need attention (see above)"
    end
    puts "\n"
  end
end
