# frozen_string_literal: true

module AIConfidence
  # Calibrates AI confidence scores based on actual trade outcomes
  # Requires ~100+ closed TradeOutcomes for meaningful calibration
  class Calibrator < ApplicationService
    MIN_OUTCOMES_FOR_CALIBRATION = 50
    CONFIDENCE_BUCKETS = {
      high: 8.0..10.0,
      medium: 6.5..8.0,
      low: 0.0..6.5,
    }.freeze

    def self.call(scope: nil, min_outcomes: MIN_OUTCOMES_FOR_CALIBRATION)
      new(scope: scope, min_outcomes: min_outcomes).call
    end

    def initialize(scope: nil, min_outcomes: MIN_OUTCOMES_FOR_CALIBRATION)
      @scope = scope || TradeOutcome.closed
      @min_outcomes = min_outcomes
    end

    def call
      return insufficient_data_response if total_outcomes < @min_outcomes

      calibration_result = {
        success: true,
        total_outcomes: total_outcomes,
        calibration: calculate_calibration,
        buckets: analyze_buckets,
        recommendations: generate_recommendations,
        calibrated_at: Time.current,
      }

      # Persist calibration for future reference
      persist_calibration(calibration_result)

      calibration_result
    rescue StandardError => e
      Rails.logger.error("[AIConfidence::Calibrator] Failed: #{e.message}")
      {
        success: false,
        error: e.message,
      }
    end

    private

    def total_outcomes
      @total_outcomes ||= @scope.count
    end

    def insufficient_data_response
      {
        success: false,
        insufficient_data: true,
        total_outcomes: total_outcomes,
        min_required: @min_outcomes,
        message: "Need at least #{@min_outcomes} closed outcomes for calibration. Currently have #{total_outcomes}.",
      }
    end

    def calculate_calibration
      buckets = analyze_buckets

      {
        overall_win_rate: TradeOutcome.win_rate(@scope),
        overall_expectancy: TradeOutcome.expectancy(@scope),
        overall_avg_r_multiple: TradeOutcome.average_r_multiple(@scope),
        confidence_correlation: calculate_confidence_correlation,
        buckets: buckets,
      }
    end

    def analyze_buckets
      CONFIDENCE_BUCKETS.map do |bucket_name, range|
        bucket_outcomes = @scope.where(ai_confidence: range)
        analyze_bucket(bucket_name, bucket_outcomes, range)
      end
    end

    def analyze_bucket(bucket_name, outcomes, range)
      return empty_bucket(bucket_name, range) if outcomes.empty?

      win_rate = TradeOutcome.win_rate(outcomes)
      expectancy = TradeOutcome.expectancy(outcomes)
      avg_r = TradeOutcome.average_r_multiple(outcomes)
      winners = outcomes.winners
      losers = outcomes.losers

      {
        bucket: bucket_name,
        confidence_range: "#{range.begin}-#{range.end}",
        count: outcomes.count,
        win_rate: win_rate,
        expectancy: expectancy,
        avg_r_multiple: avg_r,
        avg_win_r: winners.any? ? winners.average(:r_multiple)&.round(2) || 0 : 0,
        avg_loss_r: losers.any? ? losers.average(:r_multiple)&.round(2) || 0 : 0,
        total_r: outcomes.sum(:r_multiple) || 0,
        winners_count: winners.count,
        losers_count: losers.count,
        breakeven_count: outcomes.breakeven.count,
        calibration_status: determine_calibration_status(bucket_name, win_rate, expectancy),
      }
    end

    def empty_bucket(bucket_name, range)
      {
        bucket: bucket_name,
        confidence_range: "#{range.begin}-#{range.end}",
        count: 0,
        win_rate: 0,
        expectancy: 0,
        avg_r_multiple: 0,
        calibration_status: "insufficient_data",
      }
    end

    def determine_calibration_status(bucket_name, win_rate, expectancy)
      case bucket_name
      when :high
        # High confidence should have > 60% win rate and > 1.0 expectancy
        if win_rate >= 60 && expectancy >= 1.0
          "well_calibrated"
        elsif win_rate >= 50 && expectancy >= 0.5
          "moderately_calibrated"
        else
          "overconfident"
        end
      when :medium
        # Medium confidence should have 45-60% win rate and 0.3-1.0 expectancy
        if win_rate >= 45 && win_rate <= 65 && expectancy >= 0.3
          "well_calibrated"
        elsif win_rate >= 40 && expectancy >= 0.0
          "moderately_calibrated"
        else
          "needs_adjustment"
        end
      when :low
        # Low confidence can have lower win rates
        if win_rate < 50 && expectancy < 0.5
          "well_calibrated" # Low confidence = lower performance is expected
        else
          "underconfident" # Performing better than expected
        end
      end
    end

    def calculate_confidence_correlation
      # Calculate correlation between AI confidence and actual R-multiple
      outcomes = @scope.where.not(ai_confidence: nil, r_multiple: nil)
      return 0 if outcomes.count < 10

      confidences = outcomes.pluck(:ai_confidence)
      r_multiples = outcomes.pluck(:r_multiple)

      # Simple correlation coefficient
      correlation = calculate_pearson_correlation(confidences, r_multiples)
      correlation.round(3)
    end

    def calculate_pearson_correlation(x, y)
      return 0 if x.size != y.size || x.size < 2

      n = x.size
      sum_x = x.sum
      sum_y = y.sum
      sum_xy = x.zip(y).sum { |a, b| a * b }
      sum_x_sq = x.sum { |a| a * a }
      sum_y_sq = y.sum { |a| a * a }

      numerator = (n * sum_xy) - (sum_x * sum_y)
      denominator = Math.sqrt([(n * sum_x_sq) - (sum_x * sum_x), (n * sum_y_sq) - (sum_y * sum_y)].max)

      return 0 if denominator.zero?

      numerator / denominator
    end

    def generate_recommendations
      buckets = analyze_buckets
      recommendations = []

      buckets.each do |bucket|
        case bucket[:calibration_status]
        when "overconfident"
          recommendations << {
            bucket: bucket[:bucket],
            issue: "overconfident",
            message: "AI confidence #{bucket[:confidence_range]} is overconfident. " \
                     "Win rate: #{bucket[:win_rate]}%, Expectancy: #{bucket[:expectancy]}. " \
                     "Consider lowering confidence threshold or improving AI prompts.",
            suggested_action: "Lower confidence threshold for #{bucket[:bucket]} bucket or review AI evaluation criteria",
          }
        when "underconfident"
          recommendations << {
            bucket: bucket[:bucket],
            issue: "underconfident",
            message: "AI confidence #{bucket[:confidence_range]} is underconfident. " \
                     "Win rate: #{bucket[:win_rate]}%, Expectancy: #{bucket[:expectancy]}. " \
                     "Performance is better than confidence suggests.",
            suggested_action: "Consider raising confidence threshold or reviewing why low confidence trades perform well",
          }
        when "needs_adjustment"
          recommendations << {
            bucket: bucket[:bucket],
            issue: "needs_adjustment",
            message: "AI confidence #{bucket[:confidence_range]} needs adjustment. " \
                     "Win rate: #{bucket[:win_rate]}%, Expectancy: #{bucket[:expectancy]}.",
            suggested_action: "Review AI evaluation criteria and scoring for #{bucket[:bucket]} confidence range",
          }
        end
      end

      # Overall recommendations
      overall = calculate_calibration
      if overall[:confidence_correlation] < 0.3
        recommendations << {
          bucket: "overall",
          issue: "low_correlation",
          message: "Low correlation (#{overall[:confidence_correlation]}) between AI confidence and actual R-multiple. " \
                   "AI confidence may not be predictive of outcomes.",
          suggested_action: "Review AI evaluation prompts and scoring methodology",
        }
      end

      recommendations
    end

    def persist_calibration(result)
      AICalibration.create_from_calibration_result(result)
    rescue StandardError => e
      Rails.logger.error("[AIConfidence::Calibrator] Failed to persist calibration: #{e.message}")
      # Don't fail calibration if persistence fails
    end
  end
end
