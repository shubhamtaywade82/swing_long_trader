# frozen_string_literal: true

module PositionFilterable
  extend ActiveSupport::Concern
  include Filterable

  private

  # Filters Position scope by status
  # @param [ActiveRecord::Relation] scope Position scope
  # @param [String] status Position status: "open", "closed", or "all"
  # @return [ActiveRecord::Relation] Filtered scope
  def filter_positions_by_status(scope, status)
    case status.to_s
    when "open"
      scope.open
    when "closed"
      scope.closed
    else
      scope
    end
  end

  # Validates position status parameter
  # @param [String, nil] status_param Status parameter
  # @return [String] Validated status
  def validate_position_status(status_param)
    validate_enum(
      status_param,
      allowed_values: %w[open closed all],
      default_value: "all"
    )
  end

  # Validates position mode parameter
  # @param [String, nil] mode_param Mode parameter
  # @return [String] Validated mode
  def validate_position_mode(mode_param)
    validate_trading_mode(mode_param, allowed_modes: %w[live paper all])
  end
end
