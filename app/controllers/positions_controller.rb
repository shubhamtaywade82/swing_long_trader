# frozen_string_literal: true

class PositionsController < ApplicationController
  def index
    # Use session mode if no explicit mode param, but allow override
    @mode = params[:mode] || current_trading_mode
    @status = params[:status] || "all" # all, open, closed

    positions_scope = Position.regular_positions.includes(:instrument, :order, :exit_order)

    positions_scope = case @mode
                      when "live"
                        positions_scope.live
                      when "paper"
                        positions_scope.paper
                      else
                        positions_scope
                      end

    positions_scope = case @status
                      when "open"
                        positions_scope.open
                      when "closed"
                        positions_scope.closed
                      else
                        positions_scope
                      end

    @positions = positions_scope.order(opened_at: :desc).limit(100)
  end
end
