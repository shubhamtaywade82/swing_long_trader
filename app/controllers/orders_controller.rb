# frozen_string_literal: true

class OrdersController < ApplicationController
  include OrderFilterable
  include QueryBuilder

  # @api public
  # Lists orders filtered by status and transaction type
  # @param [String] status Order status: "pending", "placed", "executed", "rejected", "pending_approval", or "all"
  # @param [String] type Transaction type: "buy", "sell", or "all"
  # @return [void] Renders orders/index view
  def index
    order_params = params.permit(:status, :type)
    @status = validate_order_status(order_params[:status])
    @type = validate_order_type(order_params[:type])

    orders_scope = Order.all
    orders_scope = filter_orders_by_status(orders_scope, @status)
    orders_scope = filter_orders_by_type(orders_scope, @type)

    @orders = build_paginated_query(
      orders_scope,
      includes: [:instrument],
      order_column: :created_at,
      order_direction: :desc,
      limit: 100
    )
  end
end
