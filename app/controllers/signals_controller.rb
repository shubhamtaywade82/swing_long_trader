# frozen_string_literal: true

class SignalsController < ApplicationController
  # @api public
  # Lists trading signals filtered by status and type
  # @param [String] status Signal status: "executed", "pending", "failed", or "all"
  # @param [String] type Signal type: "live", "paper", or "all"
  # @return [void] Renders signals/index view
  def index
    signal_params = params.permit(:status, :type)
    @status = validate_signal_status(signal_params[:status])
    @type = validate_signal_type(signal_params[:type])

    signals_scope = TradingSignal.includes(:instrument, :order, :paper_position)
    signals_scope = filter_by_status(signals_scope, @status)
    signals_scope = filter_by_type(signals_scope, @type)

    @signals = signals_scope.order(signal_generated_at: :desc).limit(100)
  end

  private

  def validate_signal_status(status_param)
    %w[executed pending failed all].include?(status_param.to_s) ? status_param.to_s : "all"
  end

  def validate_signal_type(type_param)
    %w[live paper all].include?(type_param.to_s) ? type_param.to_s : current_trading_mode
  end

  def filter_by_status(scope, status)
    case status
    when "executed"
      scope.executed
    when "pending"
      scope.pending_approval
    when "failed"
      scope.failed
    else
      scope
    end
  end

  def filter_by_type(scope, type)
    case type
    when "paper"
      scope.paper
    when "live"
      scope.live
    else
      scope
    end
  end
end
