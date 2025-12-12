# frozen_string_literal: true

module Strategies
  module Swing
    # Optional job for monitoring exit conditions for open positions
    # Can be scheduled to run periodically during market hours
    # Checks stop loss, take profit, trailing stops, and time-based exits
    class ExitMonitorJob < ApplicationJob
      include JobLogging

      queue_as :default

      def perform
        # Get all active orders (pending or placed)
        active_orders = Order.where(status: %w[pending placed]).includes(:instrument)

        exits_triggered = []

        active_orders.find_each do |order|
          # Check exit conditions
          exit_check = check_exit_conditions(order)

          if exit_check[:should_exit]
            # Place exit order (opposite direction)
            exit_result = place_exit_order(order, exit_check[:reason])

            if exit_result[:success]
              exits_triggered << {
                order: order,
                exit_order: exit_result[:order],
                reason: exit_check[:reason],
              }
              Rails.logger.info(
                "[Strategies::Swing::ExitMonitorJob] Exit triggered: " \
                "#{order.symbol} - #{exit_check[:reason]}",
              )
            else
              Rails.logger.warn(
                "[Strategies::Swing::ExitMonitorJob] Exit order failed: " \
                "#{order.symbol} - #{exit_result[:error]}",
              )
            end
          end
        rescue StandardError => e
          Rails.logger.error(
            "[Strategies::Swing::ExitMonitorJob] Failed for order #{order.id}: #{e.message}",
          )
        end

        Rails.logger.info(
          "[Strategies::Swing::ExitMonitorJob] Completed: " \
          "active_orders=#{active_orders.count}, " \
          "exits_triggered=#{exits_triggered.size}",
        )

        {
          active_orders: active_orders.count,
          exits_triggered: exits_triggered,
        }
      rescue StandardError => e
        Rails.logger.error("[Strategies::Swing::ExitMonitorJob] Failed: #{e.message}")
        Telegram::Notifier.send_error_alert("Exit monitor failed: #{e.message}", context: "ExitMonitorJob")
        raise
      end

      private

      def check_exit_conditions(order)
        instrument = order.instrument
        return { should_exit: false } unless instrument

        # Get current price
        current_price = instrument.ltp
        return { should_exit: false, reason: "No current price" } unless current_price

        # Load signal metadata from order
        metadata = order.metadata_hash
        entry_price = metadata["entry_price"] || order.price || current_price
        stop_loss = metadata["stop_loss"]
        take_profit = metadata["take_profit"]
        trailing_stop_pct = metadata["trailing_stop_pct"]
        trailing_stop_amount = metadata["trailing_stop_amount"]
        entry_date = order.created_at.to_date

        # Check stop loss
        if stop_loss
          stop_loss_triggered = (order.buy? && current_price <= stop_loss) ||
                                (order.sell? && current_price >= stop_loss)
          return { should_exit: true, reason: "Stop loss triggered" } if stop_loss_triggered
        end

        # Check take profit
        if take_profit
          take_profit_triggered = (order.buy? && current_price >= take_profit) ||
                                  (order.sell? && current_price <= take_profit)
          return { should_exit: true, reason: "Take profit triggered" } if take_profit_triggered
        end

        # Check trailing stop
        if trailing_stop_pct || trailing_stop_amount
          highest_price = metadata["highest_price"] || entry_price
          lowest_price = metadata["lowest_price"] || entry_price

          # Update highest/lowest price
          if order.buy?
            highest_price = [highest_price, current_price].max
            trailing_stop = if trailing_stop_pct
                              highest_price * (1 - (trailing_stop_pct / 100.0))
                            else
                              highest_price - trailing_stop_amount
                            end
            return { should_exit: true, reason: "Trailing stop triggered" } if current_price <= trailing_stop
          elsif order.sell?
            lowest_price = [lowest_price, current_price].min
            trailing_stop = if trailing_stop_pct
                              lowest_price * (1 + (trailing_stop_pct / 100.0))
                            else
                              lowest_price + trailing_stop_amount
                            end
            return { should_exit: true, reason: "Trailing stop triggered" } if current_price >= trailing_stop
          end

          # Update metadata with new highest/lowest price
          metadata["highest_price"] = highest_price
          metadata["lowest_price"] = lowest_price
          order.update!(metadata: metadata.to_json)
        end

        # Check time-based exit (e.g., max holding period)
        max_holding_days = metadata["max_holding_days"] || 30
        holding_days = (Time.zone.today - entry_date).to_i
        if holding_days >= max_holding_days
          return { should_exit: true, reason: "Max holding period reached (#{holding_days} days)" }
        end

        { should_exit: false }
      end

      def place_exit_order(order, _reason)
        # Determine exit transaction type (opposite of entry)
        exit_transaction_type = order.buy? ? "SELL" : "BUY"

        # Place market order to exit
        Dhan::Orders.place_order(
          instrument: order.instrument,
          order_type: "MARKET",
          transaction_type: exit_transaction_type,
          quantity: order.quantity,
          client_order_id: "EXIT-#{order.client_order_id}",
          dry_run: order.dry_run,
        )
      end
    end
  end
end
