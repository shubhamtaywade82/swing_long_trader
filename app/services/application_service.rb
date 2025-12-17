# frozen_string_literal: true

class ApplicationService
  def self.call(*, **, &)
    new(*, **).call(&)
  end

  private

  # Sends a message to Telegram with optional service tag
  # Uses System Bot by default (for system/service notifications)
  #
  # @param message [String] The message to send
  # @param tag [String, nil] Optional short label like 'SL_HIT', 'TP', etc.
  # @param bot_type [Symbol] Bot type: :trading or :system (default: :system)
  # @return [void]
  def notify(message, tag: nil, bot_type: :system)
    return unless TelegramNotifier.enabled?(bot_type: bot_type)

    context = "[#{self.class.name}]"
    final_message = tag.present? ? "#{context} [#{tag}]\n\n#{message}" : "#{context} #{message}"

    TelegramNotifier.send_message(final_message, bot_type: bot_type)
  rescue StandardError => e
    Rails.logger.error("[ApplicationService] Telegram Notify Failed: #{e.class} - #{e.message}")
  end

  # Send typing indicator to Telegram
  # @param bot_type [Symbol] Bot type: :trading or :system (default: :system)
  # @return [void]
  def typing_ping(bot_type: :system)
    return unless TelegramNotifier.enabled?(bot_type: bot_type)

    TelegramNotifier.send_chat_action(action: "typing", bot_type: bot_type)
  rescue StandardError => e
    Rails.logger.error("[ApplicationService] Typing ping failed: #{e.class} - #{e.message}")
  end

  # -------- Logging ---------------------------------------------------------
  %i[info warn error debug].each do |lvl|
    define_method(:"log_#{lvl}") { |msg| Rails.logger.send(lvl, "[#{self.class.name}] #{msg}") }
  end
end
