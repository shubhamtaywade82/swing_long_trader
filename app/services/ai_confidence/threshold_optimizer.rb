# frozen_string_literal: true

module AIConfidence
  # Optimizes AI confidence thresholds based on calibration results
  class ThresholdOptimizer < ApplicationService
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
        success: true,
        current_threshold: current_threshold,
        recommended_threshold: calculate_optimal_threshold(calibration),
        rationale: generate_rationale(calibration),
        impact_estimate: estimate_impact(calibration),
      }
    end

    private

    def current_threshold
      AlgoConfig.fetch(%i[swing_trading ai_evaluation min_confidence]) || 6.5
    end

    def calculate_optimal_threshold(calibration)
      buckets = calibration[:buckets] || []
      
      # Find the lowest confidence bucket with positive expectancy
      optimal_bucket = buckets.find { |b| b[:expectancy] && b[:expectancy] > 0.5 }
      return current_threshold unless optimal_bucket

      # Use the lower bound of the optimal bucket
      range = parse_range(optimal_bucket[:confidence_range])
      range.begin
    end

    def parse_range(range_string)
      parts = range_string.split("-").map(&:to_f)
      parts[0]..parts[1]
    end

    def generate_rationale(calibration)
      buckets = calibration[:buckets] || []
      optimal_threshold = calculate_optimal_threshold(calibration)

      rationale = []
      rationale << "Current threshold: #{current_threshold}"
      rationale << "Recommended threshold: #{optimal_threshold}"

      buckets.each do |bucket|
        if bucket[:expectancy] && bucket[:expectancy] > 0.5
          rationale << "Confidence #{bucket[:confidence_range]} shows positive expectancy (#{bucket[:expectancy]})"
        end
      end

      rationale.join("\n")
    end

    def estimate_impact(calibration)
      current = current_threshold
      recommended = calculate_optimal_threshold(calibration)

      return { impact: "none", message: "Threshold unchanged" } if (current - recommended).abs < 0.1

      # Estimate how many more/fewer trades would be taken
      if recommended < current
        {
          impact: "more_trades",
          threshold_change: recommended - current,
          message: "Lowering threshold from #{current} to #{recommended} would allow more trades",
        }
      else
        {
          impact: "fewer_trades",
          threshold_change: recommended - current,
          message: "Raising threshold from #{current} to #{recommended} would filter more trades",
        }
      end
    end
  end
end
