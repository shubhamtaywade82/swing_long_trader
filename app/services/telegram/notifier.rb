# frozen_string_literal: true

module Telegram
  class Notifier < ApplicationService
    def self.send_daily_candidates(candidates)
      new.send_daily_candidates(candidates)
    end

    def self.send_tiered_candidates(final_result)
      new.send_tiered_candidates(final_result)
    end

    def self.send_signal_alert(signal)
      new.send_signal_alert(signal)
    end

    def self.send_exit_alert(signal, exit_reason:, exit_price:, pnl:)
      new.send_exit_alert(signal, exit_reason: exit_reason, exit_price: exit_price, pnl: pnl)
    end

    def self.send_portfolio_snapshot(portfolio_data)
      new.send_portfolio_snapshot(portfolio_data)
    end

    def self.send_error_alert(error_message, context: nil)
      new.send_error_alert(error_message, context: context)
    end

    def self.enabled?
      ::TelegramNotifier.enabled?
    end

    def send_daily_candidates(candidates)
      return unless enabled?(:trading)

      message = AlertFormatter.format_daily_candidates(candidates)
      send_message(message, bot_type: :trading)
    rescue StandardError => e
      Rails.logger.error("[Telegram::Notifier] Failed to send daily candidates: #{e.message}")
    end

    def send_tiered_candidates(final_result)
      return unless enabled?(:trading)

      message = AlertFormatter.format_tiered_candidates(final_result)
      send_message(message, bot_type: :trading)
    rescue StandardError => e
      Rails.logger.error("[Telegram::Notifier] Failed to send tiered candidates: #{e.message}")
    end

    def send_signal_alert(signal)
      return unless enabled?(:trading)

      message = AlertFormatter.format_signal_alert(signal)
      send_message(message, bot_type: :trading)
    rescue StandardError => e
      Rails.logger.error("[Telegram::Notifier] Failed to send signal alert: #{e.message}")
    end

    def send_exit_alert(signal, exit_reason:, exit_price:, pnl:)
      return unless enabled?(:trading)

      message = AlertFormatter.format_exit_alert(signal, exit_reason: exit_reason, exit_price: exit_price, pnl: pnl)
      send_message(message, bot_type: :trading)
    rescue StandardError => e
      Rails.logger.error("[Telegram::Notifier] Failed to send exit alert: #{e.message}")
    end

    def send_portfolio_snapshot(portfolio_data)
      return unless enabled?(:trading)

      message = AlertFormatter.format_portfolio_snapshot(portfolio_data)
      send_message(message, bot_type: :trading)
    rescue StandardError => e
      Rails.logger.error("[Telegram::Notifier] Failed to send portfolio snapshot: #{e.message}")
    end

    def send_error_alert(error_message, context: nil)
      return unless enabled?(:system)

      message = AlertFormatter.format_error_alert(error_message, context: context)
      send_message(message, bot_type: :system)
    rescue StandardError => e
      Rails.logger.error("[Telegram::Notifier] Failed to send error alert: #{e.message}")
    end

    private

    def enabled?(bot_type = nil)
      ::TelegramNotifier.enabled?(bot_type: bot_type)
    end

    def send_message(text, bot_type: nil)
      return unless text.present?
      return unless enabled?(bot_type)

      ::TelegramNotifier.send_message(text, bot_type: bot_type, parse_mode: "HTML")
    end
  end
end
