# frozen_string_literal: true

module Screeners
  class SwingScreenerJob < ApplicationJob
    include JobLogging

    queue_as :default

    def perform(instruments: nil, limit: nil)
      Rails.logger.info("[Screeners::SwingScreenerJob] Starting 4-layer decision pipeline")

      # Create screener run for isolation and tracking
      universe_size = instruments&.count || Instrument.where(segment: %w[equity index], exchange: "NSE").count
      screener_run = ScreenerRun.create!(
        screener_type: "swing",
        universe_size: universe_size,
        started_at: Time.current,
        status: "running",
        metrics: {},
      )

      Rails.logger.info("[Screeners::SwingScreenerJob] Created ScreenerRun ##{screener_run.id}")

      begin
        # Layer 1: Technical Eligibility (SwingScreener)
        # Result: 100-150 bullish candidates (sorted by score, highest first)
        Rails.logger.info("[Screeners::SwingScreenerJob] Layer 1: Technical Eligibility Screening")
        layer1_candidates = SwingScreener.call(
          instruments: instruments,
          limit: nil,
          persist_results: true,
          screener_run_id: screener_run.id,
        )
      
        # Ensure Layer 1 results are sorted by score (highest first)
        layer1_candidates = layer1_candidates.sort_by { |c| -(c[:score] || 0) }

        screener_run.update_metrics!(
          eligible_count: layer1_candidates.size,
          layer1_completed_at: Time.current.iso8601,
        )

        Rails.logger.info(
          "[Screeners::SwingScreenerJob] Layer 1 complete: #{layer1_candidates.size} candidates " \
          "(top score: #{layer1_candidates.first&.dig(:score)&.round(1)})"
        )

        return handle_empty_results(screener_run) if layer1_candidates.empty?

        # Layer 2: Trade Quality Ranking
        # Result: 30-40 high-quality setups (sorted by combined score, highest first)
        Rails.logger.info("[Screeners::SwingScreenerJob] Layer 2: Trade Quality Ranking")
        layer2_candidates = TradeQualityRanker.call(
          candidates: layer1_candidates,
          limit: 40,
          screener_run_id: screener_run.id,
        )

        screener_run.update_metrics!(
          ranked_count: layer2_candidates.size,
          layer2_completed_at: Time.current.iso8601,
        )

        Rails.logger.info(
          "[Screeners::SwingScreenerJob] Layer 2 complete: #{layer2_candidates.size} candidates " \
          "(top quality score: #{layer2_candidates.first&.dig(:trade_quality_score)&.round(1)})"
        )

        return handle_empty_results(screener_run) if layer2_candidates.empty?

        # Portfolio pre-filter before AI (save costs, avoid untradable setups)
        portfolio = CapitalAllocationPortfolio.active.first
        prefiltered_candidates = prefilter_for_portfolio(layer2_candidates, portfolio)

        screener_run.update_metrics!(
          prefiltered_count: prefiltered_candidates.size,
        )

        Rails.logger.info(
          "[Screeners::SwingScreenerJob] Pre-filtered #{layer2_candidates.size} → #{prefiltered_candidates.size} " \
          "tradable candidates before AI evaluation"
        )

        # Layer 3: AI Evaluation & Ranking
        # Result: 10-15 AI-approved candidates
        # IMPORTANT: AI evaluation runs ONLY on tradable screener results, processing highest scores first
        Rails.logger.info(
          "[Screeners::SwingScreenerJob] Layer 3: AI Evaluation " \
          "(evaluating #{prefiltered_candidates.size} tradable candidates, highest scores first)"
        )
        layer3_candidates = AIEvaluator.call(
          candidates: prefiltered_candidates,
          limit: 15,
          screener_run_id: screener_run.id,
        )
        top_ai_confidence = layer3_candidates.first&.dig(:ai_confidence)
        ai_calls = screener_run.ai_calls_count || 0

        screener_run.update_metrics!(
          ai_evaluated_count: layer3_candidates.size,
          ai_calls_count: ai_calls,
          layer3_completed_at: Time.current.iso8601,
        )

        Rails.logger.info(
          "[Screeners::SwingScreenerJob] Layer 3 complete: #{layer3_candidates.size} candidates" +
          (top_ai_confidence ? " (top AI confidence: #{top_ai_confidence.round(1)})" : " (AI disabled or rate limited)") +
          " (#{ai_calls} AI calls)"
        )

        return handle_empty_results(screener_run) if layer3_candidates.empty?

        # Layer 4: Portfolio & Capacity Filter
        # Result: 3-5 tradable positions
        Rails.logger.info("[Screeners::SwingScreenerJob] Layer 4: Portfolio & Capacity Filter")
        final_result = FinalSelector.call(
          swing_candidates: layer3_candidates,
          swing_limit: limit || 5,
          portfolio: portfolio,
          screener_run_id: screener_run.id,
        )
        screener_run.update_metrics!(
          final_count: final_result[:swing].size,
          tier_1_count: final_result[:summary][:tier_1_count],
          tier_2_count: final_result[:summary][:tier_2_count],
          tier_3_count: final_result[:summary][:tier_3_count],
          layer4_completed_at: Time.current.iso8601,
        )

        Rails.logger.info("[Screeners::SwingScreenerJob] Layer 4 complete: #{final_result[:swing].size} actionable positions")

        # Calculate and persist all compression metrics
        ScreenerRuns::MetricsCalculator.call(screener_run)

        # Mark run as completed
        screener_run.mark_completed!

        # Log health status
        health = screener_run.health_status
        if health[:healthy]
          Rails.logger.info(
            "[Screeners::SwingScreenerJob] Run ##{screener_run.id} completed successfully " \
            "(compression: #{health[:compression_efficiency]}%, " \
            "overlap: #{health[:overlap]}%)"
          )
        else
          Rails.logger.warn(
            "[Screeners::SwingScreenerJob] Run ##{screener_run.id} completed with issues: " \
            "#{health[:issues].join(', ')}"
          )
        end

        # Cache results for dashboard display
        cache_key = "swing_screener_results_#{Date.current}"
        Rails.cache.write(cache_key, final_result[:swing], expires_in: 24.hours)
        Rails.cache.write("#{cache_key}_timestamp", Time.current, expires_in: 24.hours)
        Rails.cache.write("#{cache_key}_tiers", final_result[:tiers], expires_in: 24.hours)
        Rails.cache.write("#{cache_key}_summary", final_result[:summary], expires_in: 24.hours)
        Rails.cache.write("#{cache_key}_run_id", screener_run.id, expires_in: 24.hours)

        # Broadcast update to dashboard with run_id and stage
        ActionCable.server.broadcast(
          "dashboard_updates",
          {
            type: "screener_update",
            screener_type: "swing",
            screener_run_id: screener_run.id,
            stage: "final",
            candidate_count: final_result[:swing].size,
            tier_1_count: final_result[:summary][:tier_1_count],
            tier_2_count: final_result[:summary][:tier_2_count],
            tier_3_count: final_result[:summary][:tier_3_count],
            compression_efficiency: screener_run.compression_efficiency,
          },
        )

        # Create TradeOutcomes for final actionable candidates (Tier 1)
        create_trade_outcomes_for_final_candidates(screener_run, final_result[:tiers][:tier_1])

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

        # Mark run as failed
        screener_run&.mark_failed!(e.message)

        # Mark as failed in cache
        progress_key = "swing_screener_progress_#{Date.current}"
        Rails.cache.write(progress_key, {
          status: "failed",
          error: e.message,
          failed_at: Time.current.iso8601,
          screener_run_id: screener_run&.id,
        }, expires_in: 1.hour)

        Telegram::Notifier.send_error_alert("Swing screener failed: #{e.message}", context: "SwingScreenerJob")
        raise
      end
    rescue StandardError => e
      # Fallback if screener_run creation failed
      Rails.logger.error("[Screeners::SwingScreenerJob] Critical failure: #{e.message}")
      Telegram::Notifier.send_error_alert("Swing screener critical failure: #{e.message}", context: "SwingScreenerJob")
      raise
    end

    private

    def prefilter_for_portfolio(candidates, portfolio)
      return candidates unless portfolio

      constraints = get_portfolio_constraints(portfolio)
      filtered = []
      sector_counts = {}
      current_positions = get_current_positions(portfolio)

      candidates.each do |candidate|
        # Check sector limit
        sector = get_sector(candidate)
        if sector && sector_counts[sector].to_i >= constraints[:max_per_sector]
          next
        end

        # Check capital availability
        unless has_sufficient_capital?(candidate, constraints, portfolio)
          next
        end

        # Check max positions (lightweight check)
        if current_positions.size >= constraints[:max_positions]
          next
        end

        filtered << candidate
        sector_counts[sector] = (sector_counts[sector] || 0) + 1 if sector
      end

      filtered
    end

    def get_portfolio_constraints(portfolio)
      if portfolio&.swing_risk_config
        risk_config = portfolio.swing_risk_config
        {
          max_positions: risk_config.max_open_positions || 5,
          max_capital_pct: risk_config.max_position_exposure || 15.0,
          max_per_sector: 2,
          total_equity: portfolio.total_equity || 100_000,
        }
      else
        {
          max_positions: 5,
          max_capital_pct: 15.0,
          max_per_sector: 2,
          total_equity: portfolio&.total_equity || 100_000,
        }
      end
    end

    def get_current_positions(portfolio)
      return [] unless portfolio

      portfolio.open_swing_positions.includes(:instrument).map do |pos|
        {
          symbol: pos.instrument&.symbol_name || pos.symbol,
          sector: get_sector_for_instrument(pos.instrument),
        }
      end
    end

    def get_sector(candidate)
      return nil unless candidate[:instrument_id]

      instrument = Instrument.find_by(id: candidate[:instrument_id])
      get_sector_for_instrument(instrument)
    end

    def get_sector_for_instrument(instrument)
      return nil unless instrument

      constituent = IndexConstituent.find_by(symbol: instrument.symbol_name.upcase)
      return constituent.industry if constituent&.industry.present?

      if instrument.isin.present?
        constituent = IndexConstituent.find_by(isin_code: instrument.isin.upcase)
        return constituent.industry if constituent&.industry.present?
      end

      nil
    end

    def has_sufficient_capital?(candidate, constraints, portfolio)
      return true unless portfolio

      max_position_value = constraints[:total_equity] * (constraints[:max_capital_pct] / 100.0)
      available = portfolio.available_swing_capital || portfolio.swing_capital || 0

      available >= max_position_value * 0.5
    end

    def create_trade_outcomes_for_final_candidates(screener_run, tier1_candidates)
      return if tier1_candidates.empty?

      Rails.logger.info("[Screeners::SwingScreenerJob] Creating TradeOutcomes for #{tier1_candidates.size} Tier 1 candidates")

      tier1_candidates.each do |candidate|
        result = TradeOutcomes::Creator.call(
          screener_run: screener_run,
          candidate: candidate,
          trading_mode: "paper", # Default to paper, can be overridden
        )

        if result[:success]
          Rails.logger.debug("[Screeners::SwingScreenerJob] Created TradeOutcome for #{candidate[:symbol]}")
        else
          Rails.logger.warn("[Screeners::SwingScreenerJob] Failed to create TradeOutcome for #{candidate[:symbol]}: #{result[:error]}")
        end
      end
    rescue StandardError => e
      Rails.logger.error("[Screeners::SwingScreenerJob] Failed to create TradeOutcomes: #{e.message}")
      # Don't fail the entire job if outcome creation fails
    end

    def handle_empty_results(screener_run = nil)
      Rails.logger.warn("[Screeners::SwingScreenerJob] No candidates found after screening")
      screener_run&.mark_completed! if screener_run

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

