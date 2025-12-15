# frozen_string_literal: true

class OrdersController < ApplicationController
  def index
    @status = params[:status] || "all" # all, pending, placed, executed, rejected
    @type = params[:type] || "all" # all, buy, sell
    # Note: Orders don't have live/paper distinction in the same way, but we can filter by mode if needed

    orders_scope = Order.includes(:instrument)

    orders_scope = case @status
                   when "pending"
                     orders_scope.pending
                   when "placed"
                     orders_scope.placed
                   when "executed"
                     orders_scope.executed
                   when "rejected"
                     orders_scope.rejected
                   when "pending_approval"
                     orders_scope.pending_approval
                   else
                     orders_scope
                   end

    orders_scope = case @type
                   when "buy"
                     orders_scope.where(transaction_type: "BUY")
                   when "sell"
                     orders_scope.where(transaction_type: "SELL")
                   else
                     orders_scope
                   end

    @orders = orders_scope.order(created_at: :desc).limit(100)
  end
end
