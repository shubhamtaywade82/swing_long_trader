# frozen_string_literal: true

class OrdersController < ApplicationController
  # @api public
  # Lists orders filtered by status and transaction type
  # @param [String] status Order status: "pending", "placed", "executed", "rejected", "pending_approval", or "all"
  # @param [String] type Transaction type: "buy", "sell", or "all"
  # @return [void] Renders orders/index view
  def index
    order_params = params.permit(:status, :type)
    @status = validate_order_status(order_params[:status])
    @type = validate_order_type(order_params[:type])

    orders_scope = Order.includes(:instrument)
    orders_scope = filter_by_status(orders_scope, @status)
    orders_scope = filter_by_type(orders_scope, @type)

    @orders = orders_scope.order(created_at: :desc).limit(100)
  end

  private

  def validate_order_status(status_param)
    %w[pending placed executed rejected pending_approval all].include?(status_param.to_s) ? status_param.to_s : "all"
  end

  def validate_order_type(type_param)
    %w[buy sell all].include?(type_param.to_s) ? type_param.to_s : "all"
  end

  def filter_by_status(scope, status)
    case status
    when "pending"
      scope.pending
    when "placed"
      scope.placed
    when "executed"
      scope.executed
    when "rejected"
      scope.rejected
    when "pending_approval"
      scope.pending_approval
    else
      scope
    end
  end

  def filter_by_type(scope, type)
    case type
    when "buy"
      scope.where(transaction_type: "BUY")
    when "sell"
      scope.where(transaction_type: "SELL")
    else
      scope
    end
  end
end
