# frozen_string_literal: true

module Strategies
  module Swing
    # Optional job for monitoring exit conditions for open positions
    # Can be scheduled to run periodically during market hours
    # Checks stop loss, take profit, trailing stops, and time-based exits
    class ExitMonitorJob < ApplicationJob
      include JobLogging

      # Use monitoring queue for exit monitoring
      queue_as :monitoring

      # Retry strategy: exponential backoff, max 2 attempts
      retry_on StandardError, wait: :polynomially_longer, attempts: 2

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

        # Check take profit (TP2 for ATR-based, or single TP for backward compatibility)
        tp1 = metadata["tp1"]
        tp2 = metadata["tp2"]
        tp1_hit = metadata["tp1_hit"] || false

        # Check TP1 hit - move stop to breakeven
        if tp1 && !tp1_hit
          tp1_triggered = (order.buy? && current_price >= tp1) ||
                          (order.sell? && current_price <= tp1)
          if tp1_triggered
            # Update metadata to mark TP1 as hit
            metadata["tp1_hit"] = true
            metadata["breakeven_stop"] = entry_price
            metadata["initial_stop_loss"] = stop_loss
            metadata["stop_loss"] = entry_price # Move to breakeven
            order.update!(metadata: metadata.to_json)

            Rails.logger.info(
              "[Strategies::Swing::ExitMonitorJob] TP1 hit for order #{order.client_order_id}, " \
              "stop moved to breakeven",
            )
            # Don't exit yet, continue to TP2
          end
        end

        # Check TP2 hit - exit position
        if tp2
          tp2_triggered = (order.buy? && current_price >= tp2) ||
                          (order.sell? && current_price <= tp2)
          return { should_exit: true, reason: "TP2 hit" } if tp2_triggered
        end

        # Check single take profit (backward compatibility)
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

        # Check TP1 hit (first target) - move stop to breakeven
        if position.check_tp1_hit? && !position.tp1_hit
          # Mark TP1 as hit and move stop to breakeven
          position.update!(tp1_hit: true)
          position.move_stop_to_breakeven!

          Rails.logger.info(
            "[Strategies::Swing::ExitMonitorJob] TP1 hit for #{position.symbol}, " \
            "stop moved to breakeven at #{position.entry_price}",
          )

          # Don't exit yet, continue to TP2
        end

        # Check TP2 hit (final target) - exit position
        if position.check_tp2_hit?
          return {
            should_exit: true,
            reason: "tp2_hit",
            exit_price: position.tp2,
          }
        end

        # Check take profit (backward compatibility - single TP)
        if position.take_profit && position.check_tp_hit?
          return {
            should_exit: true,
            reason: "tp_hit",
            exit_price: position.take_profit,
          }
        end

        # Check trailing stop (ATR-based or percentage-based)
        if position.check_trailing_stop?
          # ATR-based trailing stop is handled in check_trailing_stop? method
          # For percentage-based, calculate trailing stop price
          trailing_stop = if position.atr_trailing_multiplier && position.atr
                            # ATR-based trailing stop
                            if position.long?
                              position.highest_price - (position.atr * position.atr_trailing_multiplier)
                            else
                              position.lowest_price + (position.atr * position.atr_trailing_multiplier)
                            end
                          elsif position.trailing_stop_pct
                            # Percentage-based trailing stop
                            if position.long?
                              position.highest_price * (1 - (position.trailing_stop_pct / 100.0))
                            else
                              position.lowest_price * (1 + (position.trailing_stop_pct / 100.0))
                            end
                          elsif position.trailing_stop_distance
                            # Distance-based trailing stop
                            if position.long?
                              position.highest_price - position.trailing_stop_distance
                            else
                              position.lowest_price + position.trailing_stop_distance
                            end
                          else
                            position.stop_loss # Fallback to current stop loss
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

        # Get current LTP for LIMIT order price
        current_ltp = position.current_price || position.instrument.current_ltp
        unless current_ltp&.positive?
          return {
            success: false,
            error: "Current LTP not available for exit LIMIT order",
          }
        end

        # Place LIMIT order to exit (always use LIMIT, never MARKET)
        result = Dhan::Orders.place_order(
          instrument: position.instrument,
          order_type: "LIMIT",
          transaction_type: exit_transaction_type,
          quantity: position.quantity,
          price: current_ltp, # LIMIT order with current LTP
          client_order_id: "EXIT-#{position.order&.client_order_id || position.id}",
          dry_run: false,
        )

        # Update position with exit order if successful
        position.update!(exit_order: result[:order]) if result[:success] && result[:order]

        result
      end

      def place_exit_order(order, _reason)
        # Determine exit transaction type (opposite of entry)
        exit_transaction_type = order.buy? ? "SELL" : "BUY"

        # Get current LTP for LIMIT order price
        current_ltp = order.instrument.current_ltp
        unless current_ltp&.positive?
          return {
            success: false,
            error: "Current LTP not available for exit LIMIT order",
          }
        end

        # Place LIMIT order to exit (always use LIMIT, never MARKET)
        result = Dhan::Orders.place_order(
          instrument: order.instrument,
          order_type: "LIMIT",
          transaction_type: exit_transaction_type,
          quantity: order.quantity,
          price: current_ltp, # LIMIT order with current LTP
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
