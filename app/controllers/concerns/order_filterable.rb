# frozen_string_literal: true

module OrderFilterable
  extend ActiveSupport::Concern
  include Filterable

  private

  # Filters Order scope by status
  # @param [ActiveRecord::Relation] scope Order scope
  # @param [String] status Order status
  # @return [ActiveRecord::Relation] Filtered scope
  def filter_orders_by_status(scope, status)
    case status.to_s
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

  # Filters Order scope by transaction type
  # @param [ActiveRecord::Relation] scope Order scope
  # @param [String] type Transaction type: "buy" or "sell"
  # @return [ActiveRecord::Relation] Filtered scope
  def filter_orders_by_type(scope, type)
    case type.to_s
    when "buy"
      scope.where(transaction_type: "BUY")
    when "sell"
      scope.where(transaction_type: "SELL")
    else
      scope
    end
  end

  # Validates order status parameter
  # @param [String, nil] status_param Status parameter
  # @return [String] Validated status
  def validate_order_status(status_param)
    validate_enum(
      status_param,
      allowed_values: %w[pending placed executed rejected pending_approval all],
      default_value: "all"
    )
  end

  # Validates order type parameter
  # @param [String, nil] type_param Type parameter
  # @return [String] Validated type
  def validate_order_type(type_param)
    validate_enum(
      type_param,
      allowed_values: %w[buy sell all],
      default_value: "all"
    )
  end
end
