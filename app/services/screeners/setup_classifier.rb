# frozen_string_literal: true

module Screeners
  # Layer 2.5: Setup Classification
  # Determines if a high-quality candidate is READY to trade, or should WAIT
  # Called after TradeQualityRanker, before AIEvaluator
  #
  # This is the critical decision layer that separates "bullish" from "tradeable"
  # Answers: READY, WAIT_PULLBACK, WAIT_BREAKOUT, NOT_READY, IN_POSITION
  class SetupClassifier < ApplicationService
    def self.call(candidates:, portfolio: nil, screener_run_id: nil)
      new(candidates: candidates, portfolio: portfolio, screener_run_id: screener_run_id).call
    end

    def initialize(candidates:, portfolio: nil, screener_run_id: nil)
      super()
      @candidates = candidates
      @portfolio = portfolio
      @screener_run_id = screener_run_id
      @config = AlgoConfig.fetch[:swing_trading] || {}
    end

    def call
      return [] if @candidates.empty?

      Rails.logger.info(
        "[Screeners::SetupClassifier] Classifying #{@candidates.size} candidates " \
        "(after quality ranking, before AI evaluation)",
      )

      classified = @candidates.map do |candidate|
        # Load series data for SetupDetector
        series_data = load_series_data(candidate)
        next nil unless series_data

        # Classify setup using SetupDetector
        setup_result = Screeners::SetupDetector.call(
          candidate: candidate,
          daily_series: series_data[:daily_series],
          indicators: candidate[:indicators] || {},
          mtf_analysis: candidate[:multi_timeframe],
          portfolio: @portfolio,
        )

        # Add setup classification to candidate
        candidate.merge(
          setup_status: setup_result[:status],
          setup_reason: setup_result[:reason],
          invalidate_if: setup_result[:invalidate_if],
          entry_conditions: setup_result[:entry_conditions],
        )
      end.compact

      # Persist setup classification to database
      classified.each do |candidate|
        persist_setup_classification(candidate)
      end

      ready_count = classified.count { |c| c[:setup_status] == SetupDetector::READY }
      wait_count = classified.count { |c| c[:setup_status]&.start_with?("WAIT_") }
      not_ready_count = classified.count { |c| c[:setup_status] == SetupDetector::NOT_READY }

      Rails.logger.info(
        "[Screeners::SetupClassifier] Classified #{classified.size} candidates: " \
        "#{ready_count} READY, #{wait_count} WAIT, #{not_ready_count} NOT_READY",
      )

      classified
    end

    private

    def load_series_data(candidate)
      return nil unless candidate[:instrument_id]

      instrument = Instrument.find_by(id: candidate[:instrument_id])
      return nil unless instrument

      # Load daily candles for SetupDetector using CandleLoader concern
      daily_series = instrument.load_daily_candles(limit: 200)
      return nil unless daily_series&.candles&.any?

      { daily_series: daily_series }
    rescue StandardError => e
      Rails.logger.error(
        "[Screeners::SetupClassifier] Failed to load series data for #{candidate[:symbol]}: #{e.message}",
      )
      nil
    end

    def persist_setup_classification(candidate)
      return unless candidate[:instrument_id]

      screener_result = if @screener_run_id
                          ScreenerResult.find_by(
                            screener_run_id: @screener_run_id,
                            instrument_id: candidate[:instrument_id],
                            screener_type: "swing",
                          )
                        else
                          ScreenerResult.find_by(
                            instrument_id: candidate[:instrument_id],
                            screener_type: "swing",
                          )
                        end

      return unless screener_result

      # Update metadata with setup classification
      metadata = screener_result.metadata_hash.dup
      metadata[:setup_status] = candidate[:setup_status]
      metadata[:setup_reason] = candidate[:setup_reason]
      metadata[:invalidate_if] = candidate[:invalidate_if]
      metadata[:entry_conditions] = candidate[:entry_conditions]

      # Update stage to "setup_classified" (or keep as "ranked" if already set)
      new_stage = screener_result.stage == "ranked" ? "ranked" : "setup_classified"

      screener_result.update_columns(
        metadata: metadata.to_json,
        stage: new_stage,
      )
    rescue StandardError => e
      Rails.logger.error(
        "[Screeners::SetupClassifier] Failed to persist setup classification for #{candidate[:symbol]}: #{e.message}",
      )
      # Don't fail the entire classification if one save fails
    end
  end
end
