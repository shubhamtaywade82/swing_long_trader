# frozen_string_literal: true

class PositionsController < ApplicationController
  # @api public
  # Lists positions filtered by mode and status
  # @param [String] mode Trading mode: "live", "paper", or "all"
  # @param [String] status Position status: "open", "closed", or "all"
  # @return [void] Renders positions/index view
  def index
    position_params = params.permit(:mode, :status)
    @mode = validate_position_mode(position_params[:mode])
    @status = validate_position_status(position_params[:status])

    positions_scope = Position.regular_positions.includes(:instrument, :order, :exit_order)

    positions_scope = filter_by_mode(positions_scope, @mode)
    positions_scope = filter_by_status(positions_scope, @status)

    @positions = positions_scope.order(opened_at: :desc).limit(100)
  end

  private

  def validate_position_mode(mode_param)
    %w[live paper all].include?(mode_param.to_s) ? mode_param.to_s : current_trading_mode
  end

  def validate_position_status(status_param)
    %w[open closed all].include?(status_param.to_s) ? status_param.to_s : "all"
  end

  def filter_by_mode(scope, mode)
    case mode
    when "live"
      scope.live
    when "paper"
      scope.paper
    else
      scope
    end
  end

  def filter_by_status(scope, status)
    case status
    when "open"
      scope.open
    when "closed"
      scope.closed
    else
      scope
    end
  end
end
