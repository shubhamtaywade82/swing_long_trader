# frozen_string_literal: true

module SignalFilterable
  extend ActiveSupport::Concern
  include Filterable

  private

  # Filters TradingSignal scope by status
  # @param [ActiveRecord::Relation] scope TradingSignal scope
  # @param [String] status Signal status: "executed", "pending", "failed", "not_executed", or "all"
  # @return [ActiveRecord::Relation] Filtered scope
  def filter_signals_by_status(scope, status)
    case status.to_s
    when "executed"
      scope.executed
    when "pending"
      scope.pending_approval
    when "failed"
      scope.failed
    when "not_executed"
      scope.not_executed
    else
      scope
    end
  end

  # Validates signal status parameter
  # @param [String, nil] status_param Status parameter
  # @return [String] Validated status
  def validate_signal_status(status_param)
    validate_enum(
      status_param,
      allowed_values: %w[executed pending failed not_executed all],
      default_value: "all"
    )
  end
end
