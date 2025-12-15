# frozen_string_literal: true

class PositionsController < ApplicationController
  include PositionFilterable
  include QueryBuilder

  # @api public
  # Lists positions filtered by mode and status
  # @param [String] mode Trading mode: "live", "paper", or "all"
  # @param [String] status Position status: "open", "closed", or "all"
  # @return [void] Renders positions/index view
  def index
    position_params = params.permit(:mode, :status)
    @mode = validate_position_mode(position_params[:mode])
    @status = validate_position_status(position_params[:status])

    positions_scope = Position.regular_positions
    positions_scope = filter_by_trading_mode(positions_scope, @mode)
    positions_scope = filter_positions_by_status(positions_scope, @status)

    @positions = build_paginated_query(
      positions_scope,
      includes: [:instrument, :order, :exit_order],
      order_column: :opened_at,
      order_direction: :desc,
      limit: 100
    )
  end
end
