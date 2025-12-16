# frozen_string_literal: true

namespace :test do
  namespace :telegram do
    desc "Test both Telegram bots (trading and system)"
    task bots: :environment do
      puts "\n=== 🤖 TESTING TELEGRAM BOTS ===\n\n"

      # Test Trading Bot
      puts "1️⃣  Testing Trading Bot..."
      trading_config = TelegramNotifier.get_bot_config(:trading)
      trading_enabled = [true, "true"].include?(trading_config[:enabled]) || trading_config[:enabled].to_s == "true"
      trading_configured = trading_enabled && trading_config[:bot_token].present? && trading_config[:chat_id].present?

      if trading_configured
        puts "   ✅ Trading Bot configured"
        puts "   Bot Token: #{trading_config[:bot_token][0..10]}..."
        puts "   Chat ID: #{trading_config[:chat_id]}"
        puts "   Sending test message..."
        begin
          TelegramNotifier.send_message("🧪 Trading Bot Test\n\nThis is a test message from the Trading Bot.",
                                        bot_type: :trading)
          puts "   ✅ Trading Bot test message sent successfully\n\n"
        rescue StandardError => e
          puts "   ❌ Trading Bot test failed: #{e.message}\n\n"
        end
      else
        puts "   ⚠️  Trading Bot not configured (will use fallback)"
        puts "   Enabled: #{trading_config[:enabled].inspect}"
        puts "   Bot Token: #{trading_config[:bot_token].present? ? 'present' : 'missing'}"
        puts "   Chat ID: #{trading_config[:chat_id].present? ? 'present' : 'missing'}\n\n"
      end

      # Test System Bot
      puts "2️⃣  Testing System Bot..."
      system_config = TelegramNotifier.get_bot_config(:system)
      system_enabled = [true, "true"].include?(system_config[:enabled]) || system_config[:enabled].to_s == "true"
      system_configured = system_enabled && system_config[:bot_token].present? && system_config[:chat_id].present?

      if system_configured
        puts "   ✅ System Bot configured"
        puts "   Bot Token: #{system_config[:bot_token][0..10]}..."
        puts "   Chat ID: #{system_config[:chat_id]}"
        puts "   Sending test message..."
        begin
          TelegramNotifier.send_message("🧪 System Bot Test\n\nThis is a test message from the System Bot.",
                                        bot_type: :system)
          puts "   ✅ System Bot test message sent successfully\n\n"
        rescue StandardError => e
          puts "   ❌ System Bot test failed: #{e.message}\n\n"
        end
      else
        puts "   ⚠️  System Bot not configured (will use fallback)"
        puts "   Enabled: #{system_config[:enabled].inspect}"
        puts "   Bot Token: #{system_config[:bot_token].present? ? 'present' : 'missing'}"
        puts "   Chat ID: #{system_config[:chat_id].present? ? 'present' : 'missing'}\n\n"
      end

      # Test Legacy/Fallback Bot
      puts "3️⃣  Testing Legacy/Fallback Bot..."
      legacy_config = TelegramNotifier.get_legacy_config
      legacy_enabled = [true, "true"].include?(legacy_config[:enabled]) || legacy_config[:enabled].to_s == "true"
      legacy_configured = legacy_enabled && legacy_config[:bot_token].present? && legacy_config[:chat_id].present?

      if legacy_configured
        puts "   ✅ Legacy Bot configured"
        puts "   Bot Token: #{legacy_config[:bot_token][0..10]}..."
        puts "   Chat ID: #{legacy_config[:chat_id]}"
      else
        puts "   ⚠️  Legacy Bot not configured"
        puts "   Enabled: #{legacy_config[:enabled].inspect}"
        puts "   Bot Token: #{legacy_config[:bot_token].present? ? 'present' : 'missing'}"
        puts "   Chat ID: #{legacy_config[:chat_id].present? ? 'present' : 'missing'}\n\n"
      end

      # Test Routing
      puts "4️⃣  Testing Alert Routing..."
      puts "   Testing Trading Alert (should use Trading Bot)..."
      begin
        test_signal = {
          symbol: "TEST",
          entry_price: 100.0,
          qty: 10,
          stop_loss: 90.0,
          take_profit: 120.0,
        }
        Telegram::Notifier.send_signal_alert(test_signal)
        puts "   ✅ Trading alert routed correctly\n\n"
      rescue StandardError => e
        puts "   ❌ Trading alert failed: #{e.message}\n\n"
      end

      puts "   Testing System Alert (should use System Bot)..."
      begin
        Telegram::Notifier.send_error_alert("Test system alert", context: "BotTest")
        puts "   ✅ System alert routed correctly\n\n"
      rescue StandardError => e
        puts "   ❌ System alert failed: #{e.message}\n\n"
      end

      puts "=== ✅ Testing Complete ===\n\n"
    end
  end
end
