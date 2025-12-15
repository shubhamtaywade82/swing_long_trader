# frozen_string_literal: true

require "net/http"
require "uri"

# Simple Telegram notifier using Net::HTTP
# Provides class methods for sending messages and chat actions
# Supports domain-based routing: :trading (default) and :system
class TelegramNotifier
  TELEGRAM_API = "https://api.telegram.org"
  MAX_LEN      = 4000 # keep margin below Telegram's 4096 limit
  DOMAINS      = [:trading, :system].freeze

  # Send a message to Telegram
  # @param text [String] Message text
  # @param domain [Symbol] Domain (:trading or :system), defaults to :trading
  # @param parse_mode [String] Parse mode (Markdown, HTML, etc.)
  # @return [Net::HTTPResponse, nil]
  def self.notify(text, domain: :trading, parse_mode: "Markdown")
    return if text.blank?

    validate_domain!(domain)

    chunks(text).each do |chunk|
      post("sendMessage",
           bot_token: bot_token(domain),
           chat_id: chat_id(domain),
           text: chunk,
           parse_mode: parse_mode)
    end
  rescue KeyError => e
    # Handle missing ENV variables gracefully
    Rails.logger.error("[TelegramNotifier] Missing ENV variable for domain #{domain}: #{e.message}") if defined?(Rails)
    nil
  end

  # Send a message to Telegram (backward compatibility alias)
  # @param text [String] Message text
  # @param domain [Symbol] Domain (:trading or :system), defaults to :trading
  # @param parse_mode [String] Parse mode (Markdown, HTML, etc.)
  # @param chat_id [String, Integer, nil] Deprecated - use domain instead
  # @param extra_params [Hash] Additional parameters
  # @return [Net::HTTPResponse, nil]
  def self.send_message(text, domain: :trading, parse_mode: "Markdown", chat_id: nil, **extra_params)
    # Backward compatibility: if chat_id is explicitly provided, use old behavior
    if chat_id.present?
      Rails.logger.warn("[TelegramNotifier] Using deprecated chat_id parameter. Use domain: instead.") if defined?(Rails)
      chunks(text).each do |chunk|
        post("sendMessage",
             bot_token: bot_token(:trading),
             chat_id: chat_id,
             text: chunk,
             parse_mode: parse_mode,
             **extra_params)
      end
    else
      notify(text, domain: domain, parse_mode: parse_mode)
    end
  end

  # Send a chat action (typing, uploading photo, etc.)
  # @param action [String] Action type (typing, upload_photo, etc.)
  # @param domain [Symbol] Domain (:trading or :system), defaults to :trading
  # @param chat_id [String, Integer, nil] Deprecated - use domain instead
  # @return [Net::HTTPResponse, nil]
  def self.send_chat_action(action:, domain: :trading, chat_id: nil)
    # Backward compatibility: if chat_id is explicitly provided, use old behavior
    if chat_id.present?
      Rails.logger.warn("[TelegramNotifier] Using deprecated chat_id parameter. Use domain: instead.") if defined?(Rails)
      post("sendChatAction", bot_token: bot_token(:trading), chat_id: chat_id, action: action)
    else
      validate_domain!(domain)
      post("sendChatAction", bot_token: bot_token(domain), chat_id: chat_id(domain), action: action)
    end
  rescue KeyError => e
    # Handle missing ENV variables gracefully
    Rails.logger.error("[TelegramNotifier] Missing ENV variable for domain #{domain}: #{e.message}") if defined?(Rails)
    nil
  end

  # Check if Telegram is enabled (has bot tokens and chat ID)
  # @return [Boolean]
  def self.enabled?
    chat_id_present = ENV["TELEGRAM_CHAT_ID"].present?
    trading_token_present = ENV["TELEGRAM_TRADING_BOT_TOKEN"].present?
    system_token_present = ENV["TELEGRAM_SYSTEM_BOT_TOKEN"].present?
    chat_id_present && (trading_token_present || system_token_present)
  end

  # -- PRIVATE --------------------------------------------------------------

  # Get bot token for a domain
  # @param domain [Symbol] Domain (:trading or :system)
  # @return [String] Bot token
  # @raise [KeyError] if ENV variable is not set
  def self.bot_token(domain)
    case domain
    when :trading
      ENV.fetch("TELEGRAM_TRADING_BOT_TOKEN")
    when :system
      ENV.fetch("TELEGRAM_SYSTEM_BOT_TOKEN")
    end
  end

  # Get chat ID (shared for both domains)
  # @param domain [Symbol] Domain (:trading or :system) - unused but kept for API consistency
  # @return [String] Chat ID
  # @raise [KeyError] if ENV variable is not set
  def self.chat_id(_domain = nil)
    ENV.fetch("TELEGRAM_CHAT_ID")
  end

  # Validate domain parameter
  # @param domain [Symbol] Domain to validate
  # @raise [ArgumentError] if domain is invalid
  def self.validate_domain!(domain)
    return if DOMAINS.include?(domain)

    raise ArgumentError,
          "Invalid Telegram domain #{domain}. Allowed: #{DOMAINS.join(', ')}"
  end

  # Make a POST request to Telegram API
  # @param method [String] API method name
  # @param bot_token [String] Bot token (required)
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

  private_class_method :post, :bot_token, :chat_id, :validate_domain!

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
