# frozen_string_literal: true

module Orders
  # Job to process approved orders and place them via DhanHQ
  # Can be scheduled to run periodically or triggered after approval
  class ProcessApprovedJob < ApplicationJob
    include JobLogging

    queue_as :default

    def perform(order_id: nil)
      # If specific order ID provided, process only that order
      if order_id
        order = Order.find_by(id: order_id)
        return { success: false, error: 'Order not found' } unless order
        return process_order(order)
      end

      # Otherwise, process all approved orders that haven't been placed yet
      approved_orders = Order.approved
                             .where(status: 'pending')
                             .order(approved_at: :asc)

      if approved_orders.empty?
        Rails.logger.info('[Orders::ProcessApprovedJob] No approved orders to process')
        return { success: true, processed: 0, orders: [] }
      end

      results = {
        processed: 0,
        success: 0,
        failed: 0,
        orders: []
      }

      approved_orders.find_each do |order|
        result = process_order(order)
        results[:processed] += 1

        if result[:success]
          results[:success] += 1
          results[:orders] << result[:order]
        else
          results[:failed] += 1
          Rails.logger.error(
            "[Orders::ProcessApprovedJob] Failed to process order #{order.id}: #{result[:error]}"
          )
        end
      end

      Rails.logger.info(
        "[Orders::ProcessApprovedJob] Completed: " \
        "processed=#{results[:processed]}, " \
        "success=#{results[:success]}, " \
        "failed=#{results[:failed]}"
      )

      results
    rescue StandardError => e
      Rails.logger.error("[Orders::ProcessApprovedJob] Failed: #{e.message}")
      Telegram::Notifier.send_error_alert(
        "Failed to process approved orders: #{e.message}",
        context: 'ProcessApprovedJob'
      )
      raise
    end

    private

    def process_order(order)
      # Verify order is approved
      unless order.approved?
        return { success: false, error: 'Order not approved' }
      end

      # Reconstruct signal from order metadata
      signal = reconstruct_signal_from_order(order)
      return { success: false, error: 'Failed to reconstruct signal' } unless signal

      # Execute order via Dhan::Orders
      result = Dhan::Orders.place_order(
        instrument: order.instrument,
        order_type: order.order_type,
        transaction_type: order.transaction_type,
        quantity: order.quantity,
        price: order.price,
        trigger_price: order.trigger_price,
        client_order_id: order.client_order_id,
        dry_run: order.dry_run
      )

      if result[:success]
        Rails.logger.info(
          "[Orders::ProcessApprovedJob] Order placed: #{order.symbol} " \
          "#{order.transaction_type} #{order.quantity} @ #{order.price || 'Market'}"
        )

        # Send notification
        send_order_placed_notification(order, result[:order])

        { success: true, order: result[:order] }
      else
        Rails.logger.error(
          "[Orders::ProcessApprovedJob] Order placement failed: #{order.symbol} - #{result[:error]}"
        )

        # Update order status
        order.update(
          status: 'failed',
          error_message: result[:error]
        )

        { success: false, error: result[:error], order: order }
      end
    rescue StandardError => e
      Rails.logger.error(
        "[Orders::ProcessApprovedJob] Error processing order #{order.id}: #{e.message}"
      )
      order.update(status: 'failed', error_message: e.message) if order
      { success: false, error: e.message }
    end

    def reconstruct_signal_from_order(order)
      metadata = order.metadata_hash
      return nil unless metadata

      {
        instrument_id: order.instrument_id,
        symbol: order.symbol,
        direction: order.buy? ? :long : :short,
        entry_price: order.price || order.instrument.ltp,
        qty: order.quantity,
        stop_loss: metadata['stop_loss'],
        take_profit: metadata['take_profit'],
        confidence: metadata['confidence']
      }
    end

    def send_order_placed_notification(original_order, placed_order)
      message = "✅ <b>Approved Order Placed</b>\n\n"
      message += "Symbol: #{placed_order.symbol}\n"
      message += "Type: #{placed_order.transaction_type} #{placed_order.order_type}\n"
      message += "Quantity: #{placed_order.quantity}\n"
      message += "Price: #{placed_order.price ? "₹#{placed_order.price}" : 'Market'}\n"
      message += "Status: #{placed_order.status}\n"
      message += "Order ID: #{placed_order.client_order_id}\n"
      message += "\nOriginally approved: #{original_order.approved_at}"

      Telegram::Notifier.send_error_alert(message, context: 'Approved Order Placed')
    rescue StandardError => e
      Rails.logger.error(
        "[Orders::ProcessApprovedJob] Failed to send notification: #{e.message}"
      )
    end
  end
end

