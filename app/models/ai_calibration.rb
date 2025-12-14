# frozen_string_literal: true

# Stores AI confidence calibration results for persistence
class AICalibration < ApplicationRecord
  validates :calibrated_at, presence: true
  validates :total_outcomes, presence: true, numericality: { greater_than: 0 }

  scope :recent, -> { order(calibrated_at: :desc) }
  scope :latest, -> { recent.first }

  def calibration_hash
    return {} if calibration_data.blank?

    calibration_data.is_a?(Hash) ? calibration_data : JSON.parse(calibration_data)
  rescue JSON::ParserError
    {}
  end

  def buckets
    calibration_hash["buckets"] || []
  end

  def overall_win_rate
    calibration_hash.dig("overall_win_rate") || 0
  end

  def overall_expectancy
    calibration_hash.dig("overall_expectancy") || 0
  end

  def confidence_correlation
    calibration_hash.dig("confidence_correlation") || 0
  end

  def self.create_from_calibration_result(result)
    return nil unless result[:success]

    create!(
      total_outcomes: result[:total_outcomes],
      calibrated_at: result[:calibrated_at] || Time.current,
      calibration_data: {
        overall_win_rate: result.dig(:calibration, :overall_win_rate),
        overall_expectancy: result.dig(:calibration, :overall_expectancy),
        overall_avg_r_multiple: result.dig(:calibration, :overall_avg_r_multiple),
        confidence_correlation: result.dig(:calibration, :confidence_correlation),
        buckets: result[:buckets],
        recommendations: result[:recommendations],
      },
    )
  end
end
