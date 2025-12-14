# frozen_string_literal: true

module AIConfidence
  # Generates comprehensive calibration reports
  class ReportGenerator < ApplicationService
    def self.call(calibration_result: nil, scope: nil)
      new(calibration_result: calibration_result, scope: scope).call
    end

    def initialize(calibration_result: nil, scope: nil)
      @calibration_result = calibration_result
      @scope = scope || TradeOutcome.closed
    end

    def call
      calibration = @calibration_result || AIConfidence::Calibrator.call(scope: @scope)
      return { success: false, error: "Calibration failed" } unless calibration[:success]

      {
        summary: generate_summary(calibration),
        bucket_analysis: generate_bucket_analysis(calibration),
        recommendations: calibration[:recommendations] || [],
        threshold_optimization: generate_threshold_analysis(calibration),
        performance_by_tier: analyze_by_tier,
        performance_by_stage: analyze_by_stage,
      }
    end

    private

    def generate_summary(calibration)
      cal = calibration[:calibration]
      {
        total_outcomes: calibration[:total_outcomes],
        overall_win_rate: cal[:overall_win_rate],
        overall_expectancy: cal[:overall_expectancy],
        overall_avg_r_multiple: cal[:overall_avg_r_multiple],
        confidence_correlation: cal[:confidence_correlation],
        calibration_quality: determine_overall_quality(cal),
      }
    end

    def determine_overall_quality(cal)
      correlation = cal[:confidence_correlation] || 0
      expectancy = cal[:overall_expectancy] || 0

      if correlation > 0.5 && expectancy > 0.5
        "excellent"
      elsif correlation > 0.3 && expectancy > 0.3
        "good"
      elsif correlation > 0.1
        "fair"
      else
        "poor"
      end
    end

    def generate_bucket_analysis(calibration)
      calibration[:buckets] || []
    end

    def generate_threshold_analysis(calibration)
      ThresholdOptimizer.call(calibration_result: calibration)
    end

    def analyze_by_tier
      tiers = %w[tier_1 tier_2 tier_3]
      tiers.map do |tier|
        tier_outcomes = @scope.where(tier: tier)
        {
          tier: tier,
          count: tier_outcomes.count,
          win_rate: TradeOutcome.win_rate(tier_outcomes),
          expectancy: TradeOutcome.expectancy(tier_outcomes),
          avg_r_multiple: TradeOutcome.average_r_multiple(tier_outcomes),
        }
      end
    end

    def analyze_by_stage
      stages = %w[screener ranked ai_evaluated final]
      stages.map do |stage|
        # Find outcomes from screener results at this stage
        stage_outcomes = @scope.joins(:screener_run)
                                .joins("INNER JOIN screener_results ON screener_results.screener_run_id = screener_runs.id")
                                .where("screener_results.stage = ? AND screener_results.instrument_id = trade_outcomes.instrument_id", stage)
                                .distinct

        {
          stage: stage,
          count: stage_outcomes.count,
          win_rate: TradeOutcome.win_rate(stage_outcomes),
          expectancy: TradeOutcome.expectancy(stage_outcomes),
          avg_r_multiple: TradeOutcome.average_r_multiple(stage_outcomes),
        }
      end
    end
  end
end
