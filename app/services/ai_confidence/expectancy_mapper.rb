# frozen_string_literal: true

module AIConfidence
  # Maps AI confidence scores to expected R-multiple based on historical outcomes
  class ExpectancyMapper < ApplicationService
    def self.call(confidence_score, scope: nil)
      new(scope: scope).map(confidence_score)
    end

    def initialize(scope: nil)
      @scope = scope || TradeOutcome.closed
      @calibration = load_calibration
    end

    def map(confidence_score)
      return default_expectancy unless @calibration

      # Find the bucket this confidence falls into
      bucket = find_bucket_for_confidence(confidence_score)
      return default_expectancy unless bucket

      {
        expected_r_multiple: bucket[:expectancy] || 0,
        expected_win_rate: bucket[:win_rate] || 0,
        bucket: bucket[:bucket],
        calibration_quality: bucket[:calibration_status],
        confidence: confidence_score,
      }
    end

    private

    def load_calibration
      # Load latest calibration if available
      # In production, this could be cached or stored in a Calibration model
      result = AIConfidence::Calibrator.call(scope: @scope)
      return nil unless result[:success]

      result[:calibration]
    end

    def find_bucket_for_confidence(confidence_score)
      return nil unless confidence_score

      buckets = @calibration[:buckets] || []
      buckets.find do |bucket|
        range = parse_range(bucket[:confidence_range])
        range.include?(confidence_score)
      end
    end

    def parse_range(range_string)
      # Parse "6.5-8.0" into range
      parts = range_string.split("-").map(&:to_f)
      parts[0]..parts[1]
    end

    def default_expectancy
      {
        expected_r_multiple: 0,
        expected_win_rate: 0,
        bucket: :unknown,
        calibration_quality: "no_calibration",
        confidence: nil,
      }
    end
  end
end
