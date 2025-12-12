# frozen_string_literal: true

namespace :test do
  namespace :alerts do
    desc "Test all Telegram alert types"
    task all: :environment do
      puts "\n=== 📢 TESTING ALL ALERT TYPES ===\n\n"

      unless ENV["TELEGRAM_BOT_TOKEN"].present? && ENV["TELEGRAM_CHAT_ID"].present?
        puts "⚠️  Telegram credentials not configured"
        puts "   Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in .env"
        puts "   Skipping alert tests...\n\n"
        exit 0
      end

      results = {}

      # 1. Test Signal Alert
      puts "1️⃣  Testing Signal Alert..."
      begin
        test_signal = {
          instrument_id: 1,
          symbol: "TEST",
          direction: :long,
          entry_price: 100.0,
          qty: 10,
          stop_loss: 90.0,
          take_profit: 120.0,
          confidence: 85,
        }
        Telegram::Notifier.send_signal_alert(test_signal)
        results[:signal] = { status: :success, message: "Signal alert sent" }
        puts "   ✅ Signal alert sent\n\n"
      rescue StandardError => e
        results[:signal] = { status: :failed, message: "Error: #{e.message}" }
        puts "   ❌ Signal alert failed: #{e.message}\n\n"
      end

      # 2. Test Error Alert
      puts "2️⃣  Testing Error Alert..."
      begin
        Telegram::Notifier.send_error_alert("Test error message", context: "Test Alert")
        results[:error] = { status: :success, message: "Error alert sent" }
        puts "   ✅ Error alert sent\n\n"
      rescue StandardError => e
        results[:error] = { status: :failed, message: "Error: #{e.message}" }
        puts "   ❌ Error alert failed: #{e.message}\n\n"
      end

      # 3. Test Info Alert
      puts "3️⃣  Testing Info Alert..."
      begin
        Telegram::Notifier.send_alert("Test info message", context: "Test Alert")
        results[:info] = { status: :success, message: "Info alert sent" }
        puts "   ✅ Info alert sent\n\n"
      rescue StandardError => e
        results[:info] = { status: :failed, message: "Error: #{e.message}" }
        puts "   ❌ Info alert failed: #{e.message}\n\n"
      end

      # 4. Test Order Placement Alert
      puts "4️⃣  Testing Order Placement Alert..."
      begin
        test_order = {
          symbol: "TEST",
          transaction_type: "BUY",
          order_type: "MARKET",
          quantity: 10,
          price: 100.0,
          status: "placed",
          client_order_id: "TEST-ORDER-123",
        }
        message = "📊 <b>Test Order Placed</b>\n\n"
        message += "Symbol: #{test_order[:symbol]}\n"
        message += "Type: #{test_order[:transaction_type]} #{test_order[:order_type]}\n"
        message += "Quantity: #{test_order[:quantity]}\n"
        message += "Price: ₹#{test_order[:price]}\n"
        message += "Status: #{test_order[:status]}\n"
        message += "Order ID: #{test_order[:client_order_id]}"
        Telegram::Notifier.send_alert(message, context: "Order Placement")
        results[:order] = { status: :success, message: "Order alert sent" }
        puts "   ✅ Order alert sent\n\n"
      rescue StandardError => e
        results[:order] = { status: :failed, message: "Error: #{e.message}" }
        puts "   ❌ Order alert failed: #{e.message}\n\n"
      end

      # 5. Test Job Failure Alert
      puts "5️⃣  Testing Job Failure Alert..."
      begin
        Telegram::Notifier.send_error_alert(
          "Test job failure: SampleJob failed with error",
          context: "Job Failure",
        )
        results[:job_failure] = { status: :success, message: "Job failure alert sent" }
        puts "   ✅ Job failure alert sent\n\n"
      rescue StandardError => e
        results[:job_failure] = { status: :failed, message: "Error: #{e.message}" }
        puts "   ❌ Job failure alert failed: #{e.message}\n\n"
      end

      # 6. Test Approval Request Alert
      puts "6️⃣  Testing Approval Request Alert..."
      begin
        message = "🚨 <b>Manual Approval Required</b> 🚨\n\n"
        message += "A new trade signal for <b>TEST</b> requires your approval.\n\n"
        message += "<b>Order Details:</b>\n"
        message += "  Direction: BUY\n"
        message += "  Quantity: 10\n"
        message += "  Entry Price: ₹100.00\n"
        message += "  Order ID: TEST-123\n\n"
        message += "To approve, run: `rails orders:approve[TEST-123,<your_name>]`"
        Telegram::Notifier.send_alert(message, context: "Manual Approval")
        results[:approval] = { status: :success, message: "Approval request alert sent" }
        puts "   ✅ Approval request alert sent\n\n"
      rescue StandardError => e
        results[:approval] = { status: :failed, message: "Error: #{e.message}" }
        puts "   ❌ Approval request alert failed: #{e.message}\n\n"
      end

      # Summary
      puts "\n=== 📊 ALERT TEST SUMMARY ===\n"
      results.each do |type, result|
        status_icon = result[:status] == :success ? "✅" : "❌"
        puts "#{status_icon} #{type.to_s.upcase}: #{result[:message]}"
      end

      all_passed = results.values.all? { |r| r[:status] == :success }
      puts "\n"

      if all_passed
        puts "✅ All alert types tested successfully!"
        puts "   Check your Telegram chat to verify messages were received.\n"
      else
        puts "⚠️  Some alert tests failed - review above\n"
      end

      puts "\n"
    end

    desc "Test signal alert only"
    task signal: :environment do
      puts "\n=== 📢 TESTING SIGNAL ALERT ===\n\n"
      test_signal = {
        instrument_id: 1,
        symbol: "TEST",
        direction: :long,
        entry_price: 100.0,
        qty: 10,
        stop_loss: 90.0,
        take_profit: 120.0,
        confidence: 85,
      }
      Telegram::Notifier.send_signal_alert(test_signal)
      puts "✅ Signal alert sent - check your Telegram chat\n\n"
    rescue StandardError => e
      puts "❌ Error: #{e.message}\n\n"
    end

    desc "Test error alert only"
    task error: :environment do
      puts "\n=== 📢 TESTING ERROR ALERT ===\n\n"
      Telegram::Notifier.send_error_alert("Test error message", context: "Test Alert")
      puts "✅ Error alert sent - check your Telegram chat\n\n"
    rescue StandardError => e
      puts "❌ Error: #{e.message}\n\n"
    end
  end

  namespace :dry_run do
    desc "Check dry-run mode configuration"
    task check: :environment do
      puts "\n=== 🔍 DRY-RUN MODE CHECK ===\n\n"

      dry_run_env = ENV.fetch("DRY_RUN", nil)
      dry_run_setting = Setting.fetch("execution.dry_run", false)

      puts "Environment Variable (DRY_RUN): #{dry_run_env || 'not set'}"
      puts "Setting (execution.dry_run): #{dry_run_setting}"

      if dry_run_env == "true" || dry_run_setting == true
        puts "\n✅ Dry-run mode is ENABLED"
        puts "   All orders will be logged but NOT sent to DhanHQ"
      else
        puts "\n⚠️  Dry-run mode is DISABLED"
        puts "   Orders will be sent to DhanHQ (LIVE TRADING)"
      end

      puts "\nTo enable dry-run mode:"
      puts "  export DRY_RUN=true"
      puts "  OR"
      puts "  rails runner \"Setting.put('execution.dry_run', true)\""
      puts "\n"
    end

    desc "Enable dry-run mode"
    task enable: :environment do
      puts "\n=== ✅ ENABLING DRY-RUN MODE ===\n\n"
      Setting.put("execution.dry_run", true)
      puts "✅ Dry-run mode enabled in settings"
      puts "   All orders will be logged but NOT sent to DhanHQ"
      puts "\nNote: You may also need to set DRY_RUN=true in your environment\n"
    end

    desc "Disable dry-run mode"
    task disable: :environment do
      puts "\n=== ⚠️  DISABLING DRY-RUN MODE ===\n\n"
      Setting.put("execution.dry_run", false)
      puts "⚠️  Dry-run mode disabled in settings"
      puts "   Orders will be sent to DhanHQ (LIVE TRADING)"
      puts "\n⚠️  WARNING: This enables live trading. Use with caution!\n"
    end
  end
end
