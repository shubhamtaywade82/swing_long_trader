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
        # Get all open positions (preferred) or active orders (fallback)
        open_positions = Position.open.includes(:instrument, :order)
        active_orders = Order.where(status: %w[pending placed]).includes(:instrument)

        exits_triggered = []

        # Check positions first (more accurate)
        open_positions.find_each do |position|
          # Update current price
          current_price = position.instrument.ltp
          next unless current_price

          position.update!(current_price: current_price)
          position.update_highest_lowest_price!
          position.update_unrealized_pnl!

          # Check exit conditions
          exit_check = check_exit_conditions_for_position(position)

          if exit_check[:should_exit]
            # Place exit order
            exit_result = place_exit_order_for_position(position, exit_check[:reason])

            if exit_result[:success]
              # Update position
              position.mark_as_closed!(
                exit_price: exit_check[:exit_price] || current_price,
                exit_reason: exit_check[:reason],
                exit_order: exit_result[:order],
              )

              exits_triggered << {
                position: position,
                exit_order: exit_result[:order],
                reason: exit_check[:reason],
              }

              Rails.logger.info(
                "[Strategies::Swing::ExitMonitorJob] Exit triggered: " \
                "#{position.symbol} - #{exit_check[:reason]}",
              )
            else
              Rails.logger.warn(
                "[Strategies::Swing::ExitMonitorJob] Exit order failed: " \
                "#{position.symbol} - #{exit_result[:error]}",
              )
            end
          end
        rescue StandardError => e
          Rails.logger.error(
            "[Strategies::Swing::ExitMonitorJob] Failed for position #{position.id}: #{e.message}",
          )
        end

        # Fallback: Check orders if no positions found
        if open_positions.empty?
          active_orders.find_each do |order|
            exit_check = check_exit_conditions(order)

            if exit_check[:should_exit]
              exit_result = place_exit_order(order, exit_check[:reason])

              if exit_result[:success]
                exits_triggered << {
                  order: order,
                  exit_order: exit_result[:order],
                  reason: exit_check[:reason],
                }
              end
            end
          end
        end

        Rails.logger.info(
          "[Strategies::Swing::ExitMonitorJob] Completed: " \
          "open_positions=#{open_positions.count}, " \
          "exits_triggered=#{exits_triggered.size}",
        )

        {
          open_positions: open_positions.count,
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

      def check_exit_conditions_for_position(position)
        current_price = position.current_price

        # Check stop loss
        if position.check_sl_hit?
          return {
            should_exit: true,
            reason: "sl_hit",
            exit_price: position.stop_loss,
          }
        end

        # Check take profit
        if position.check_tp_hit?
          return {
            should_exit: true,
            reason: "tp_hit",
            exit_price: position.take_profit,
          }
        end

        # Check trailing stop
        if position.check_trailing_stop?
          trailing_stop = if position.long?
                            position.highest_price * (1 - (position.trailing_stop_pct / 100.0))
                          else
                            position.lowest_price * (1 + (position.trailing_stop_pct / 100.0))
                          end

          return {
            should_exit: true,
            reason: "trailing_stop",
            exit_price: trailing_stop,
          }
        end

        # Check time-based exit
        max_holding_days = position.metadata_hash["max_holding_days"] || 30
        if position.days_held >= max_holding_days
          return {
            should_exit: true,
            reason: "time_based",
            exit_price: current_price,
          }
        end

        { should_exit: false }
      end

      def place_exit_order_for_position(position, _reason)
        # Determine exit transaction type (opposite of entry)
        exit_transaction_type = position.long? ? "SELL" : "BUY"

        # Place market order to exit
        result = Dhan::Orders.place_order(
          instrument: position.instrument,
          order_type: "MARKET",
          transaction_type: exit_transaction_type,
          quantity: position.quantity,
          client_order_id: "EXIT-#{position.order&.client_order_id || position.id}",
          dry_run: false,
        )

        # Update position with exit order if successful
        if result[:success] && result[:order]
          position.update!(exit_order: result[:order])
        end

        result
      end

      def place_exit_order(order, _reason)
        # Determine exit transaction type (opposite of entry)
        exit_transaction_type = order.buy? ? "SELL" : "BUY"

        # Place market order to exit
        result = Dhan::Orders.place_order(
          instrument: order.instrument,
          order_type: "MARKET",
          transaction_type: exit_transaction_type,
          quantity: order.quantity,
          client_order_id: "EXIT-#{order.client_order_id}",
          dry_run: order.dry_run,
        )

        # Update position if exists
        if result[:success] && result[:order]
          position = Position.find_by(order: order)
          if position
            position.mark_as_closed!(
              exit_price: result[:order].average_price || order.price,
              exit_reason: "exit_order_placed",
              exit_order: result[:order],
            )
          end
        end

        result
      end
    end
  end
end
