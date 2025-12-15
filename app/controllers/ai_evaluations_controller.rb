# frozen_string_literal: true

class AiEvaluationsController < ApplicationController
  include SignalFilterable
  include QueryBuilder

  # @api public
  # Lists trading signals with AI evaluation data
  # @param [String] mode Trading mode: "live" or "paper"
  # @param [String] status Signal status: "executed", "pending", "failed", "not_executed", or "all"
  # @param [String] ai_only Filter to only signals with AI data: "true" or "false"
  # @return [void] Renders ai_evaluations/index view
  def index
    ai_params = params.permit(:mode, :status, :ai_only)
    @mode = validate_trading_mode(ai_params[:mode])
    @status = validate_signal_status(ai_params[:status])

    signals_scope = TradingSignal.all
    signals_scope = filter_by_trading_mode(signals_scope, @mode)
    signals_scope = filter_signals_by_status(signals_scope, @status)

    @signals = build_paginated_query(
      signals_scope.recent,
      includes: [:instrument],
      limit: 100,
    )

    # Extract AI data from signal metadata
    @signals_with_ai = extract_ai_data(@signals)

    # Filter to only show signals with AI data if requested
    return unless ai_params[:ai_only] == "true"

    @signals_with_ai = @signals_with_ai.select { |s| s[:has_ai_data] }
  end

  private

  def extract_ai_data(signals)
    signals.map do |signal|
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
  end
end
