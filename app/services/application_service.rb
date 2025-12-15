# frozen_string_literal: true

class ApplicationService
  def self.call(*, **, &)
    new(*, **).call(&)
  end

  private

  # Sends a message to Telegram with optional service tag
  #
  # @param message [String] The message to send
  # @param tag [String, nil] Optional short label like 'SL_HIT', 'TP', etc.
  # @param domain [Symbol] Domain (:trading or :system), defaults to :trading
  # @return [void]
  def notify(message, tag: nil, domain: :trading)
    return unless TelegramNotifier.enabled?

    context = "[#{self.class.name}]"
    final_message = tag.present? ? "#{context} [#{tag}]\n\n#{message}" : "#{context} #{message}"

    TelegramNotifier.notify(final_message, domain: domain)
  rescue StandardError => e
    Rails.logger.error("[ApplicationService] Telegram Notify Failed: #{e.class} - #{e.message}")
  end

  # Send typing indicator to Telegram
  # @return [void]
  def typing_ping
    return unless TelegramNotifier.enabled?

    TelegramNotifier.send_chat_action(action: "typing")
  rescue StandardError => e
    Rails.logger.error("[ApplicationService] Typing ping failed: #{e.class} - #{e.message}")
  end

  # -------- Logging ---------------------------------------------------------
  %i[info warn error debug].each do |lvl|
    define_method(:"log_#{lvl}") { |msg| Rails.logger.send(lvl, "[#{self.class.name}] #{msg}") }
  end
end
