# frozen_string_literal: true

module ScreenerRuns
  # Calculates compression metrics and health indicators for ScreenerRun
  class MetricsCalculator < ApplicationService
    def self.call(screener_run)
      new(screener_run: screener_run).call
    end

    def initialize(screener_run:)
      @screener_run = screener_run
    end

    def call
      metrics = calculate_all_metrics
      @screener_run.update_metrics!(metrics)
      
      {
        success: true,
        metrics: metrics,
      }
    rescue StandardError => e
      Rails.logger.error("[ScreenerRuns::MetricsCalculator] Failed: #{e.message}")
      {
        success: false,
        error: e.message,
      }
    end

    private

    def calculate_all_metrics
      base_metrics = @screener_run.metrics_hash || {}
      
      # Get counts from database
      results = @screener_run.screener_results
      
      base_metrics.merge(
        # Layer counts
        eligible_count: results.by_stage("screener").count,
        ranked_count: results.by_stage("ranked").count,
        ai_evaluated_count: results.ai_evaluated.count,
        final_count: results.by_stage("final").count,
        
        # Compression metrics
        compression_efficiency: calculate_compression_efficiency,
        compression_ratio: calculate_compression_ratio,
        
        # AI metrics
        ai_cost: @screener_run.ai_cost || 0,
        ai_calls_count: @screener_run.ai_calls_count || 0,
        ai_success_rate: calculate_ai_success_rate,
        
        # Overlap metrics
        overlap_with_prev_run: calculate_overlap_with_previous_run,
        new_candidates_count: calculate_new_candidates_count,
        
        # Quality metrics
        avg_screener_score: calculate_avg_score(results.by_stage("screener"), :score),
        avg_quality_score: calculate_avg_score(results.by_stage("ranked"), :trade_quality_score),
        avg_ai_confidence: calculate_avg_score(results.ai_evaluated, :ai_confidence),
        
        # Tier distribution
        tier_1_count: results.where("metadata::text LIKE '%tier_1%' OR stage = 'final'").count,
        tier_2_count: results.where("metadata::text LIKE '%tier_2%'").count,
        tier_3_count: results.where("metadata::text LIKE '%tier_3%'").count,
        
        # Calculated at
        metrics_calculated_at: Time.current.iso8601,
      )
    end

    def calculate_compression_efficiency
      eligible = @screener_run.metrics_hash["eligible_count"] || 0
      final = @screener_run.metrics_hash["final_count"] || 0
      
      return 0 if eligible.zero?
      
      (final.to_f / eligible * 100).round(2)
    end

    def calculate_compression_ratio
      eligible = @screener_run.metrics_hash["eligible_count"] || 0
      final = @screener_run.metrics_hash["final_count"] || 0
      
      return 0 if final.zero?
      
      (eligible.to_f / final).round(2)
    end

    def calculate_ai_success_rate
      total = @screener_run.ai_calls_count || 0
      return 0 if total.zero?
      
      evaluated = @screener_run.screener_results.ai_evaluated.count
      (evaluated.to_f / total * 100).round(2)
    end

    def calculate_overlap_with_previous_run
      prev_run = get_previous_run
      return 0 unless prev_run
      
      current_symbols = @screener_run.screener_results
                                     .by_stage("final")
                                     .pluck(:symbol)
                                     .to_set
      
      prev_symbols = prev_run.screener_results
                             .by_stage("final")
                             .pluck(:symbol)
                             .to_set
      
      return 0 if current_symbols.empty?
      
      overlap_count = (current_symbols & prev_symbols).size
      (overlap_count.to_f / current_symbols.size * 100).round(2)
    end

    def calculate_new_candidates_count
      prev_run = get_previous_run
      return @screener_run.screener_results.by_stage("final").count unless prev_run
      
      current_symbols = @screener_run.screener_results
                                     .by_stage("final")
                                     .pluck(:symbol)
                                     .to_set
      
      prev_symbols = prev_run.screener_results
                             .by_stage("final")
                             .pluck(:symbol)
                             .to_set
      
      (current_symbols - prev_symbols).size
    end

    def get_previous_run
      ScreenerRun.where(screener_type: @screener_run.screener_type)
                 .where("started_at < ?", @screener_run.started_at)
                 .completed
                 .order(started_at: :desc)
                 .first
    end

    def calculate_avg_score(scope, field)
      scope.where.not(field => nil).average(field)&.round(2) || 0
    end
  end
end
