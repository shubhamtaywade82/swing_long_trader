# frozen_string_literal: true

class SignalsController < ApplicationController
  include SignalFilterable
  include QueryBuilder

  # @api public
  # Lists trading signals filtered by status and type
  # @param [String] status Signal status: "executed", "pending", "failed", or "all"
  # @param [String] type Signal type: "live", "paper", or "all"
  # @return [void] Renders signals/index view
  def index
    signal_params = params.permit(:status, :type)
    @status = validate_signal_status(signal_params[:status])
    @type = validate_signal_type(signal_params[:type])

    signals_scope = TradingSignal.all
    signals_scope = filter_signals_by_status(signals_scope, @status)
    signals_scope = filter_by_trading_mode(signals_scope, @type)

    @signals = build_paginated_query(
      signals_scope,
      includes: [:instrument, :order, :paper_position],
      order_column: :signal_generated_at,
      order_direction: :desc,
      limit: 100
    )
  end

  private

  def validate_signal_type(type_param)
    validate_trading_mode(type_param, allowed_modes: %w[live paper all])
  end
end
