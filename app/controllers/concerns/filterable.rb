# frozen_string_literal: true

module Filterable
  extend ActiveSupport::Concern

  private

  # Filters a scope by trading mode (live/paper/all)
  # @param [ActiveRecord::Relation] scope The ActiveRecord scope to filter
  # @param [String] mode Trading mode: "live", "paper", or "all"
  # @return [ActiveRecord::Relation] Filtered scope
  def filter_by_trading_mode(scope, mode)
    case mode.to_s
    when "live"
      scope.respond_to?(:live) ? scope.live : scope
    when "paper"
      scope.respond_to?(:paper) ? scope.paper : scope
    else
      scope
    end
  end

  # Validates and normalizes trading mode parameter
  # @param [String, nil] mode_param The mode parameter from request
  # @param [Array<String>] allowed_modes Allowed mode values (default: ["live", "paper", "all"])
  # @param [String] default_mode Default mode if invalid (default: current_trading_mode)
  # @return [String] Validated mode
  def validate_trading_mode(mode_param, allowed_modes: %w[live paper all], default_mode: nil)
    default_mode ||= current_trading_mode
    allowed_modes.include?(mode_param.to_s) ? mode_param.to_s : default_mode
  end

  # Validates a parameter against a list of allowed values
  # @param [String, nil] param The parameter to validate
  # @param [Array<String>] allowed_values List of allowed values
  # @param [String] default_value Default value if invalid
  # @return [String] Validated parameter value
  def validate_enum(param, allowed_values:, default_value:)
    allowed_values.include?(param.to_s) ? param.to_s : default_value
  end
end
