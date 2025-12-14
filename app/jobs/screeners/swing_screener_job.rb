# frozen_string_literal: true

module Screeners
  class SwingScreenerJob < ApplicationJob
    include JobLogging

    queue_as :default

    def perform(instruments: nil, limit: nil)
      Rails.logger.info("[Screeners::SwingScreenerJob] Starting 4-layer decision pipeline")

      # Layer 1: Technical Eligibility (SwingScreener)
      # Result: 100-150 bullish candidates (sorted by score, highest first)
      Rails.logger.info("[Screeners::SwingScreenerJob] Layer 1: Technical Eligibility Screening")
      layer1_candidates = SwingScreener.call(instruments: instruments, limit: nil, persist_results: true)
      
      # Ensure Layer 1 results are sorted by score (highest first)
      layer1_candidates = layer1_candidates.sort_by { |c| -(c[:score] || 0) }
      
      Rails.logger.info(
        "[Screeners::SwingScreenerJob] Layer 1 complete: #{layer1_candidates.size} candidates " \
        "(top score: #{layer1_candidates.first&.dig(:score)&.round(1)})"
      )

      return handle_empty_results if layer1_candidates.empty?

      # Layer 2: Trade Quality Ranking
      # Result: 30-40 high-quality setups (sorted by combined score, highest first)
      Rails.logger.info("[Screeners::SwingScreenerJob] Layer 2: Trade Quality Ranking")
      layer2_candidates = TradeQualityRanker.call(candidates: layer1_candidates, limit: 40)
      Rails.logger.info(
        "[Screeners::SwingScreenerJob] Layer 2 complete: #{layer2_candidates.size} candidates " \
        "(top quality score: #{layer2_candidates.first&.dig(:trade_quality_score)&.round(1)})"
      )

      return handle_empty_results if layer2_candidates.empty?

      # Layer 3: AI Evaluation & Ranking
      # Result: 10-15 AI-approved candidates
      # IMPORTANT: AI evaluation runs ONLY on screener results, processing highest scores first
      Rails.logger.info(
        "[Screeners::SwingScreenerJob] Layer 3: AI Evaluation " \
        "(evaluating #{layer2_candidates.size} screener results, highest scores first)"
      )
      layer3_candidates = AIEvaluator.call(candidates: layer2_candidates, limit: 15)
      Rails.logger.info(
        "[Screeners::SwingScreenerJob] Layer 3 complete: #{layer3_candidates.size} candidates " \
        "(top AI confidence: #{layer3_candidates.first&.dig(:ai_confidence)&.round(1)})"
      )

      return handle_empty_results if layer3_candidates.empty?

      # Layer 4: Portfolio & Capacity Filter
      # Result: 3-5 tradable positions
      Rails.logger.info("[Screeners::SwingScreenerJob] Layer 4: Portfolio & Capacity Filter")
      portfolio = CapitalAllocationPortfolio.active.first
      final_result = FinalSelector.call(
        swing_candidates: layer3_candidates,
        swing_limit: limit || 5,
        portfolio: portfolio,
      )
      Rails.logger.info("[Screeners::SwingScreenerJob] Layer 4 complete: #{final_result[:swing].size} actionable positions")

      # Cache results for dashboard display
      cache_key = "swing_screener_results_#{Date.current}"
      Rails.cache.write(cache_key, final_result[:swing], expires_in: 24.hours)
      Rails.cache.write("#{cache_key}_timestamp", Time.current, expires_in: 24.hours)
      Rails.cache.write("#{cache_key}_tiers", final_result[:tiers], expires_in: 24.hours)
      Rails.cache.write("#{cache_key}_summary", final_result[:summary], expires_in: 24.hours)

      # Broadcast update to dashboard
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "screener_update",
          screener_type: "swing",
          candidate_count: final_result[:swing].size,
          tier_1_count: final_result[:summary][:tier_1_count],
          tier_2_count: final_result[:summary][:tier_2_count],
          tier_3_count: final_result[:summary][:tier_3_count],
        },
      )

      # Send tiered results to Telegram
      if final_result[:swing].any? && AlgoConfig.fetch(%i[notifications telegram notify_screener_results])
        Telegram::Notifier.send_tiered_candidates(final_result)
      end

      # Optionally trigger swing analysis job for tier 1 candidates only
      if final_result[:tiers][:tier_1].any? && AlgoConfig.fetch(%i[swing_trading strategy auto_analyze])
        tier1_instrument_ids = final_result[:tiers][:tier_1].map { |c| c[:instrument_id] }.compact
        Strategies::Swing::AnalysisJob.perform_later(tier1_instrument_ids)
        Rails.logger.info("[Screeners::SwingScreenerJob] Triggered analysis job for #{tier1_instrument_ids.size} tier 1 candidates")
      end

      final_result
    rescue StandardError => e
      Rails.logger.error("[Screeners::SwingScreenerJob] Failed: #{e.message}")
      Rails.logger.error("[Screeners::SwingScreenerJob] Backtrace: #{e.backtrace.first(5).join("\n")}")

      # Mark as failed
      progress_key = "swing_screener_progress_#{Date.current}"
      Rails.cache.write(progress_key, {
        status: "failed",
        error: e.message,
        failed_at: Time.current.iso8601,
      }, expires_in: 1.hour)

      Telegram::Notifier.send_error_alert("Swing screener failed: #{e.message}", context: "SwingScreenerJob")
      raise
    end

    private

    def handle_empty_results
      Rails.logger.warn("[Screeners::SwingScreenerJob] No candidates found after screening")
      {
        swing: [],
        longterm: [],
        summary: {
          swing_count: 0,
          swing_selected: 0,
          tier_1_count: 0,
          tier_2_count: 0,
          tier_3_count: 0,
        },
        tiers: {
          tier_1: [],
          tier_2: [],
          tier_3: [],
        },
      }
    end
  end
end

