# frozen_string_literal: true

require "net/http"
require "uri"

# Simple Telegram notifier using Net::HTTP
# Provides class methods for sending messages and chat actions
# Supports dual bot configuration: trading bot and system bot
class TelegramNotifier
  TELEGRAM_API = "https://api.telegram.org"
  MAX_LEN      = 4000 # keep margin below Telegram's 4096 limit

  # Send a message to Telegram
  # @param text [String] Message text
  # @param bot_type [Symbol] Bot type: :trading, :system, or nil (auto-detect from config)
  # @param chat_id [String, Integer, nil] Chat ID (falls back to config/ENV)
  # @param extra_params [Hash] Additional parameters (parse_mode, etc.)
  # @return [Net::HTTPResponse, nil]
  def self.send_message(text, bot_type: nil, chat_id: nil, **extra_params)
    return if text.blank?

    # Get bot configuration based on bot_type
    bot_config = get_bot_config(bot_type)
    return unless bot_config[:enabled]

    chat_id ||= bot_config[:chat_id]
    return if chat_id.blank?

    bot_token = bot_config[:bot_token]
    return if bot_token.blank?

    chunks(text).each do |chunk|
      post("sendMessage",
           bot_token: bot_token,
           chat_id: chat_id,
           text: chunk,
           **extra_params)
    end
  end

  # Send a chat action (typing, uploading photo, etc.)
  # @param action [String] Action type (typing, upload_photo, etc.)
  # @param bot_type [Symbol] Bot type: :trading, :system, or nil (auto-detect from config)
  # @param chat_id [String, Integer, nil] Chat ID (falls back to config/ENV)
  # @return [Net::HTTPResponse, nil]
  def self.send_chat_action(action:, bot_type: nil, chat_id: nil)
    bot_config = get_bot_config(bot_type)
    return unless bot_config[:enabled]

    chat_id ||= bot_config[:chat_id]
    return if chat_id.blank?

    bot_token = bot_config[:bot_token]
    return if bot_token.blank?

    post("sendChatAction", bot_token: bot_token, chat_id: chat_id, action: action)
  end

  # Check if Telegram is enabled (has bot token and chat ID)
  # @param bot_type [Symbol, nil] Bot type to check, or nil to check if any bot is enabled
  # @return [Boolean]
  def self.enabled?(bot_type: nil)
    if bot_type
      config = get_bot_config(bot_type)
      config[:enabled] && config[:bot_token].present? && config[:chat_id].present?
    else
      # Check if at least one bot is enabled
      trading_enabled = enabled?(bot_type: :trading)
      system_enabled = enabled?(bot_type: :system)
      legacy_enabled = ENV["TELEGRAM_BOT_TOKEN"].present? && ENV["TELEGRAM_CHAT_ID"].present?
      trading_enabled || system_enabled || legacy_enabled
    end
  end

  # Get bot configuration for a specific bot type
  # @param bot_type [Symbol, nil] :trading, :system, or nil (returns legacy config)
  # @return [Hash] Configuration hash with :enabled, :bot_token, :chat_id
  def self.get_bot_config(bot_type)
    return get_legacy_config if bot_type.nil?

    config_key = "telegram_#{bot_type}".to_sym # rubocop:disable Lint/SymbolConversion
    config = begin
      AlgoConfig.fetch([:notifications, config_key])
    rescue StandardError
      nil
    end

    return get_legacy_config unless config.is_a?(Hash)

    # Handle both symbol and string keys from YAML
    enabled = config[:enabled] || config["enabled"]
    bot_token = config[:bot_token] || config["bot_token"]
    chat_id = config[:chat_id] || config["chat_id"]

    # Validate chat_id is not a placeholder
    valid_chat_id = chat_id.present? &&
                    chat_id.to_s != "your_#{bot_type}_chat_id" &&
                    chat_id.to_s != "your_chat_id" &&
                    !chat_id.to_s.include?("your_") &&
                    !chat_id.to_s.include?("YOUR_") &&
                    chat_id.to_s != ""

    if enabled && bot_token.present? && valid_chat_id
      {
        enabled: [true, "true"].include?(enabled) || enabled.to_s == "true",
        bot_token: bot_token,
        chat_id: chat_id,
      }
    else
      # Fallback to legacy config if separate bot not configured
      get_legacy_config
    end
  end

  # Get legacy single bot configuration
  # @return [Hash] Configuration hash
  def self.get_legacy_config
    config = begin
      AlgoConfig.fetch(%i[notifications telegram])
    rescue StandardError
      nil
    end

    return fallback_to_env unless config.is_a?(Hash)

    # Handle both symbol and string keys from YAML
    enabled = config[:enabled] || config["enabled"]
    bot_token = config[:bot_token] || config["bot_token"]
    chat_id = config[:chat_id] || config["chat_id"]

    if enabled && bot_token.present? && chat_id.present?
      {
        enabled: enabled,
        bot_token: bot_token,
        chat_id: chat_id,
      }
    else
      fallback_to_env
    end
  end

  # Fallback to ENV variables if no config found
  # @return [Hash] Configuration hash from ENV
  def self.fallback_to_env
    {
      enabled: ENV["TELEGRAM_BOT_TOKEN"].present? && ENV["TELEGRAM_CHAT_ID"].present?,
      bot_token: ENV.fetch("TELEGRAM_BOT_TOKEN", nil),
      chat_id: ENV.fetch("TELEGRAM_CHAT_ID", nil),
    }
  end

  # -- PRIVATE --------------------------------------------------------------

  # Make a POST request to Telegram API
  # @param method [String] API method name
  # @param bot_token [String] Bot token to use
  # @param params [Hash] Parameters to send
  # @return [Net::HTTPResponse, nil]
  def self.post(method, bot_token:, **params)
    return if bot_token.blank?

    uri = URI("#{TELEGRAM_API}/bot#{bot_token}/#{method}")
    res = Net::HTTP.post_form(uri, params)

    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.error("[TelegramNotifier] #{method} failed: #{res.body}") if defined?(Rails)
      return nil
    end

    res
  rescue StandardError => e
    Rails.logger.error("[TelegramNotifier] #{method} error: #{e.class} - #{e.message}") if defined?(Rails)
    nil
  end

  private_class_method :post

  # Split text into safe chunks under MAX_LEN
  # Tries to split on paragraph boundaries first
  # @param text [String] Text to chunk
  # @return [Array<String>] Array of text chunks
  def self.chunks(text)
    return [] if text.blank?

    lines = text.split("\n")
    chunks = []
    buf = ""

    lines.each do |line|
      test_buf = buf.empty? ? line : "#{buf}\n#{line}"
      if test_buf.length > MAX_LEN
        chunks << buf.strip unless buf.empty?
        buf = line
      else
        buf = test_buf
      end
    end

    chunks << buf.strip unless buf.empty?
    chunks
  end

  private_class_method :chunks
end
