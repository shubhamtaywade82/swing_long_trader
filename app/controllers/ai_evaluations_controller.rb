# frozen_string_literal: true

class AiEvaluationsController < ApplicationController
  def index
    # Show signals with AI evaluation data
    @mode = params[:mode] || current_trading_mode
    @status = params[:status] || "all" # all, executed, pending, failed

    signals_scope = TradingSignal.includes(:instrument)

    # Filter by mode
    signals_scope = case @mode
                    when "live"
                      signals_scope.live
                    when "paper"
                      signals_scope.paper
                    else
                      signals_scope
                    end

    # Filter by status
    signals_scope = case @status
                    when "executed"
                      signals_scope.executed
                    when "pending"
                      signals_scope.pending_approval
                    when "failed"
                      signals_scope.failed
                    when "not_executed"
                      signals_scope.not_executed
                    else
                      signals_scope
                    end

    @signals = signals_scope.recent.limit(100)

    # Extract AI data from signal metadata
    @signals_with_ai = @signals.map do |signal|
      metadata = signal.signal_metadata_hash
      ai_data = metadata.dig("ai_evaluation") || metadata.dig("ai") || {}

      {
        signal: signal,
        ai_score: ai_data["ai_score"] || ai_data[:ai_score],
        ai_confidence: ai_data["ai_confidence"] || ai_data[:ai_confidence],
        ai_summary: ai_data["ai_summary"] || ai_data[:ai_summary],
        ai_risk: ai_data["ai_risk"] || ai_data[:ai_risk],
        timeframe_alignment: ai_data["timeframe_alignment"] || ai_data[:timeframe_alignment],
        entry_timing: ai_data["entry_timing"] || ai_data[:entry_timing],
        has_ai_data: ai_data.present?,
      }
    end

    # Filter to only show signals with AI data if requested
    return unless params[:ai_only] == "true"

    @signals_with_ai = @signals_with_ai.select { |s| s[:has_ai_data] }
  end
end
