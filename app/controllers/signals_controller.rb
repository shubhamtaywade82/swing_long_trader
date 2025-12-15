# frozen_string_literal: true

class SignalsController < ApplicationController
  def index
    @status = params[:status] || "all" # all, executed, pending, failed
    # Use session mode if no explicit type param
    @type = params[:type] || current_trading_mode

    signals_scope = TradingSignal.includes(:instrument, :order, :paper_position)

    signals_scope = case @status
                    when "executed"
                      signals_scope.executed
                    when "pending"
                      signals_scope.pending_approval
                    when "failed"
                      signals_scope.failed
                    else
                      signals_scope
                    end

    signals_scope = case @type
                    when "paper"
                      signals_scope.paper
                    when "live"
                      signals_scope.live
                    else
                      signals_scope
                    end

    @signals = signals_scope.order(signal_generated_at: :desc).limit(100)
  end
end
