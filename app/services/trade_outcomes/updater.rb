# frozen_string_literal: true

module TradeOutcomes
  # Updates TradeOutcome when position is closed
  class Updater < ApplicationService
    def self.call(outcome:, exit_price:, exit_reason:, exit_time: nil)
      new(
        outcome: outcome,
        exit_price: exit_price,
        exit_reason: exit_reason,
        exit_time: exit_time,
      ).call
    end

    def initialize(outcome:, exit_price:, exit_reason:, exit_time: nil)
      @outcome = outcome
      @exit_price = exit_price
      @exit_reason = exit_reason
      @exit_time = exit_time || Time.current
    end

    def call
      return { success: false, error: "Outcome already closed" } if @outcome.closed?

      @outcome.mark_closed!(
        exit_price: @exit_price,
        exit_reason: @exit_reason,
        exit_time: @exit_time,
      )

      {
        success: true,
        outcome: @outcome,
        r_multiple: @outcome.r_multiple,
        pnl: @outcome.pnl,
      }
    rescue StandardError => e
      Rails.logger.error("[TradeOutcomes::Updater] Failed to update outcome: #{e.message}")
      {
        success: false,
        error: e.message,
      }
    end
  end
end
