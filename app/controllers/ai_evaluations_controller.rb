# frozen_string_literal: true

class AiEvaluationsController < ApplicationController
  # @api public
  # Lists trading signals with AI evaluation data
  # @param [String] mode Trading mode: "live" or "paper"
  # @param [String] status Signal status: "executed", "pending", "failed", "not_executed", or "all"
  # @param [String] ai_only Filter to only signals with AI data: "true" or "false"
  # @return [void] Renders ai_evaluations/index view
  def index
    ai_params = params.permit(:mode, :status, :ai_only)
    @mode = validate_trading_mode(ai_params[:mode])
    @status = validate_ai_status(ai_params[:status])

    signals_scope = TradingSignal.includes(:instrument)
    signals_scope = filter_by_mode(signals_scope, @mode)
    signals_scope = filter_by_status(signals_scope, @status)

    @signals = signals_scope.recent.limit(100)

    # Extract AI data from signal metadata
    @signals_with_ai = extract_ai_data(@signals)

    # Filter to only show signals with AI data if requested
    if ai_params[:ai_only] == "true"
      @signals_with_ai = @signals_with_ai.select { |s| s[:has_ai_data] }
    end
  end

  private

  def validate_trading_mode(mode_param)
    %w[live paper all].include?(mode_param.to_s) ? mode_param.to_s : current_trading_mode
  end

  def validate_ai_status(status_param)
    %w[executed pending failed not_executed all].include?(status_param.to_s) ? status_param.to_s : "all"
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
    when "executed"
      scope.executed
    when "pending"
      scope.pending_approval
    when "failed"
      scope.failed
    when "not_executed"
      scope.not_executed
    else
      scope
    end
  end

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
