# frozen_string_literal: true

module ScreenerRuns
  # Generates comprehensive reports for ScreenerRun analysis
  class ReportGenerator < ApplicationService
    def self.call(screener_run)
      new(screener_run: screener_run).call
    end

    def initialize(screener_run:)
      @screener_run = screener_run
    end

    def call
      {
        run_summary: run_summary,
        compression_metrics: compression_metrics,
        quality_metrics: quality_metrics,
        ai_metrics: ai_metrics,
        overlap_analysis: overlap_analysis,
        health_status: @screener_run.health_status,
        tier_distribution: tier_distribution,
      }
    end

    private

    def run_summary
      {
        id: @screener_run.id,
        screener_type: @screener_run.screener_type,
        started_at: @screener_run.started_at,
        completed_at: @screener_run.completed_at,
        duration_seconds: @screener_run.duration_seconds,
        status: @screener_run.status,
        universe_size: @screener_run.universe_size,
      }
    end

    def compression_metrics
      m = @screener_run.metrics_hash
      {
        eligible_count: m["eligible_count"] || 0,
        ranked_count: m["ranked_count"] || 0,
        ai_evaluated_count: m["ai_evaluated_count"] || 0,
        final_count: m["final_count"] || 0,
        compression_efficiency: @screener_run.compression_efficiency,
        compression_ratio: @screener_run.compression_ratio,
      }
    end

    def quality_metrics
      m = @screener_run.metrics_hash
      {
        avg_screener_score: m["avg_screener_score"] || 0,
        avg_quality_score: m["avg_quality_score"] || 0,
        avg_ai_confidence: m["avg_ai_confidence"] || 0,
      }
    end

    def ai_metrics
      m = @screener_run.metrics_hash
      {
        ai_calls_count: @screener_run.ai_calls_count || 0,
        ai_cost: @screener_run.ai_cost || 0,
        ai_success_rate: m["ai_success_rate"] || 0,
        cost_per_evaluation: calculate_cost_per_evaluation,
      }
    end

    def overlap_analysis
      m = @screener_run.metrics_hash
      {
        overlap_with_prev_run: m["overlap_with_prev_run"] || 0,
        new_candidates_count: m["new_candidates_count"] || 0,
      }
    end

    def tier_distribution
      m = @screener_run.metrics_hash
      {
        tier_1: m["tier_1_count"] || 0,
        tier_2: m["tier_2_count"] || 0,
        tier_3: m["tier_3_count"] || 0,
      }
    end

    def calculate_cost_per_evaluation
      calls = @screener_run.ai_calls_count || 0
      cost = @screener_run.ai_cost || 0
      return 0 if calls.zero?

      (cost / calls).round(4)
    end
  end
end
