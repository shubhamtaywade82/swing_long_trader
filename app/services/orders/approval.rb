# frozen_string_literal: true

module Orders
  # Handles manual approval/rejection of orders
  class Approval < ApplicationService
    def self.approve(order_id, approved_by: 'system')
      new(order_id: order_id, action: :approve, approved_by: approved_by).call
    end

    def self.reject(order_id, reason: nil, rejected_by: 'system')
      new(order_id: order_id, action: :reject, rejected_by: rejected_by, reason: reason).call
    end

    def initialize(order_id:, action:, approved_by: nil, rejected_by: nil, reason: nil)
      @order_id = order_id
      @action = action
      @approved_by = approved_by
      @rejected_by = rejected_by
      @reason = reason
    end

    def call
      order = Order.find_by(id: @order_id)
      return { success: false, error: 'Order not found' } unless order
      return { success: false, error: 'Order already processed' } if order.approved? || order.rejected?
      return { success: false, error: 'Order does not require approval' } unless order.requires_approval?

      case @action
      when :approve
        approve_order(order)
      when :reject
        reject_order(order)
      else
        { success: false, error: 'Invalid action' }
      end
    end

    private

    def approve_order(order)
      order.update!(
        approved_at: Time.current,
        approved_by: @approved_by || 'system',
        metadata: update_metadata(order, { approved_at: Time.current, approved_by: @approved_by })
      )

      # Send notification
      send_approval_notification(order)

      # Enqueue job to process approved order
      Orders::ProcessApprovedJob.perform_later(order_id: order.id)

      { success: true, order: order, message: 'Order approved and queued for placement' }
    rescue StandardError => e
      Rails.logger.error("[Orders::Approval] Failed to approve order #{order.id}: #{e.message}")
      { success: false, error: e.message }
    end

    def reject_order(order)
      order.update!(
        rejected_at: Time.current,
        rejected_by: @rejected_by || 'system',
        rejection_reason: @reason,
        status: 'cancelled',
        metadata: update_metadata(order, {
          rejected_at: Time.current,
          rejected_by: @rejected_by,
          rejection_reason: @reason
        })
      )

      # Send notification
      send_rejection_notification(order)

      { success: true, order: order, message: 'Order rejected' }
    rescue StandardError => e
      Rails.logger.error("[Orders::Approval] Failed to reject order #{order.id}: #{e.message}")
      { success: false, error: e.message }
    end

    def update_metadata(order, new_data)
      existing = order.metadata_hash
      existing.merge(new_data).to_json
    end

    def send_approval_notification(order)
      message = "✅ <b>Order Approved</b>\n\n"
      message += "Symbol: #{order.symbol}\n"
      message += "Type: #{order.transaction_type} #{order.order_type}\n"
      message += "Quantity: #{order.quantity}\n"
      message += "Approved by: #{order.approved_by}\n"
      message += "Order ID: #{order.client_order_id}"

      Telegram::Notifier.send_error_alert(message, context: 'Order Approval')
    rescue StandardError => e
      Rails.logger.error("[Orders::Approval] Failed to send approval notification: #{e.message}")
    end

    def send_rejection_notification(order)
      message = "❌ <b>Order Rejected</b>\n\n"
      message += "Symbol: #{order.symbol}\n"
      message += "Type: #{order.transaction_type} #{order.order_type}\n"
      message += "Quantity: #{order.quantity}\n"
      message += "Rejected by: #{order.rejected_by}\n"
      message += "Reason: #{order.rejection_reason || 'Not specified'}\n"
      message += "Order ID: #{order.client_order_id}"

      Telegram::Notifier.send_error_alert(message, context: 'Order Rejection')
    rescue StandardError => e
      Rails.logger.error("[Orders::Approval] Failed to send rejection notification: #{e.message}")
    end
  end
end

