# frozen_string_literal: true

namespace :telegram do
  namespace :diagnose do
    desc "Diagnose Telegram bot configuration and routing"
    task bots: :environment do
      puts "\n=== 🔍 TELEGRAM BOT DIAGNOSTICS ===\n\n"

      # Check Environment Variables
      puts "1️⃣  Environment Variables:"
      puts "   TELEGRAM_TRADING_BOT_TOKEN: #{ENV['TELEGRAM_TRADING_BOT_TOKEN'].present? ? ENV['TELEGRAM_TRADING_BOT_TOKEN'][0..15] + '...' : 'NOT SET'}"
      puts "   TELEGRAM_TRADING_CHAT_ID: #{ENV['TELEGRAM_TRADING_CHAT_ID'] || 'NOT SET'}"
      puts "   TELEGRAM_SYSTEM_BOT_TOKEN: #{ENV['TELEGRAM_SYSTEM_BOT_TOKEN'].present? ? ENV['TELEGRAM_SYSTEM_BOT_TOKEN'][0..15] + '...' : 'NOT SET'}"
      puts "   TELEGRAM_SYSTEM_CHAT_ID: #{ENV['TELEGRAM_SYSTEM_CHAT_ID'] || 'NOT SET'}"
      puts "   TELEGRAM_BOT_TOKEN (legacy): #{ENV['TELEGRAM_BOT_TOKEN'].present? ? ENV['TELEGRAM_BOT_TOKEN'][0..15] + '...' : 'NOT SET'}"
      puts "   TELEGRAM_CHAT_ID (legacy): #{ENV['TELEGRAM_CHAT_ID'] || 'NOT SET'}"
      puts ""

      # Check Config File
      puts "2️⃣  Config File (config/algo.yml):"
      trading_config = begin
        AlgoConfig.fetch(%i[notifications telegram_trading])
      rescue StandardError
        nil
      end
      system_config = begin
        AlgoConfig.fetch(%i[notifications telegram_system])
      rescue StandardError
        nil
      end
      legacy_config = begin
        AlgoConfig.fetch(%i[notifications telegram])
      rescue StandardError
        nil
      end

      if trading_config
        trading_chat_id = trading_config[:chat_id] || trading_config["chat_id"]
        trading_bot_token = trading_config[:bot_token] || trading_config["bot_token"]
        puts "   telegram_trading:"
        puts "     enabled: #{trading_config[:enabled] || trading_config['enabled']}"
        puts "     bot_token: #{trading_bot_token.present? ? trading_bot_token[0..15] + '...' : 'NOT SET'}"
        puts "     chat_id: #{trading_chat_id || 'NOT SET'}"
        puts "     chat_id_valid: #{trading_chat_id.present? && !trading_chat_id.to_s.include?('your_') ? '✅' : '❌ (placeholder or missing)'}"
      else
        puts "   telegram_trading: NOT FOUND"
      end

      if system_config
        system_chat_id = system_config[:chat_id] || system_config["chat_id"]
        system_bot_token = system_config[:bot_token] || system_config["bot_token"]
        puts "   telegram_system:"
        puts "     enabled: #{system_config[:enabled] || system_config['enabled']}"
        puts "     bot_token: #{system_bot_token.present? ? system_bot_token[0..15] + '...' : 'NOT SET'}"
        puts "     chat_id: #{system_chat_id || 'NOT SET'}"
        puts "     chat_id_valid: #{system_chat_id.present? && !system_chat_id.to_s.include?('your_') ? '✅' : '❌ (placeholder or missing)'}"
      else
        puts "   telegram_system: NOT FOUND"
      end

      if legacy_config
        legacy_chat_id = legacy_config[:chat_id] || legacy_config["chat_id"]
        legacy_bot_token = legacy_config[:bot_token] || legacy_config["bot_token"]
        puts "   telegram (legacy):"
        puts "     enabled: #{legacy_config[:enabled] || legacy_config['enabled']}"
        puts "     bot_token: #{legacy_bot_token.present? ? legacy_bot_token[0..15] + '...' : 'NOT SET'}"
        puts "     chat_id: #{legacy_chat_id || 'NOT SET'}"
      else
        puts "   telegram (legacy): NOT FOUND"
      end
      puts ""

      # Check Resolved Configs
      puts "3️⃣  Resolved Bot Configurations:"
      trading_resolved = TelegramNotifier.get_bot_config(:trading)
      system_resolved = TelegramNotifier.get_bot_config(:system)
      legacy_resolved = TelegramNotifier.get_legacy_config

      puts "   Trading Bot (resolved):"
      puts "     enabled: #{trading_resolved[:enabled]}"
      puts "     bot_token: #{trading_resolved[:bot_token]&.[](0..15)}..."
      puts "     chat_id: #{trading_resolved[:chat_id]}"
      puts "     source: #{trading_resolved[:chat_id] == (legacy_config&.dig(:chat_id) || legacy_config&.dig('chat_id')) ? 'Legacy (fallback)' : 'Trading Bot Config'}"

      puts "   System Bot (resolved):"
      puts "     enabled: #{system_resolved[:enabled]}"
      puts "     bot_token: #{system_resolved[:bot_token]&.[](0..15)}..."
      puts "     chat_id: #{system_resolved[:chat_id]}"
      puts "     source: #{system_resolved[:chat_id] == (legacy_config&.dig(:chat_id) || legacy_config&.dig('chat_id')) ? 'Legacy (fallback)' : 'System Bot Config'}"

      puts "   Legacy Bot (resolved):"
      puts "     enabled: #{legacy_resolved[:enabled]}"
      puts "     bot_token: #{legacy_resolved[:bot_token]&.[](0..15)}..."
      puts "     chat_id: #{legacy_resolved[:chat_id]}"
      puts ""

      # Check if bots are different
      puts "4️⃣  Bot Separation Status:"
      same_bot_token = trading_resolved[:bot_token] == system_resolved[:bot_token]
      same_chat_id = trading_resolved[:chat_id] == system_resolved[:chat_id]

      if same_bot_token && same_chat_id
        puts "   ⚠️  WARNING: Both bots are using the SAME configuration!"
        puts "   Both messages will go to the same bot/chat."
        puts ""
        puts "   To fix this, set separate environment variables:"
        puts "   - TELEGRAM_SYSTEM_BOT_TOKEN (different bot token, or same if using different chat)"
        puts "   - TELEGRAM_SYSTEM_CHAT_ID (different chat ID - can be same bot, different chat/channel)"
      else
        puts "   ✅ Bots are configured separately"
        puts "   Trading Bot → Chat ID: #{trading_resolved[:chat_id]}"
        puts "   System Bot → Chat ID: #{system_resolved[:chat_id]}"
      end
      puts ""

      # Recommendations
      puts "5️⃣  Recommendations:"
      if system_resolved[:chat_id].blank? || system_resolved[:chat_id].to_s.include?("your_")
        puts "   ❌ System bot has placeholder or missing chat_id"
        puts "   → Set TELEGRAM_SYSTEM_CHAT_ID in .env file"
        puts "   → Or update config/algo.yml with real chat_id"
      end

      if same_chat_id
        puts "   ⚠️  Both bots are sending to the same chat_id"
        puts "   → Set TELEGRAM_SYSTEM_CHAT_ID to a different chat/channel ID"
        puts "   → You can use the same bot token but different chat IDs"
      end

      puts ""
      puts "=== ✅ Diagnostics Complete ===\n\n"
    end
  end
end
