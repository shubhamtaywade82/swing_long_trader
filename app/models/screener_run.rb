# frozen_string_literal: true

class ScreenerRun < ApplicationRecord
  has_many :screener_results, dependent: :destroy

  validates :screener_type, presence: true, inclusion: { in: %w[swing longterm] }
  validates :universe_size, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[running completed failed] }

  scope :swing, -> { where(screener_type: "swing") }
  scope :longterm, -> { where(screener_type: "longterm") }
  scope :recent, -> { order(started_at: :desc) }
  scope :completed, -> { where(status: "completed") }
  scope :running, -> { where(status: "running") }
  scope :failed, -> { where(status: "failed") }

  def metrics_hash
    return {} if metrics.blank?

    metrics.is_a?(Hash) ? metrics : JSON.parse(metrics)
  rescue JSON::ParserError
    {}
  end

  def update_metrics!(new_metrics)
    current = metrics_hash
    updated = current.merge(new_metrics.stringify_keys)
    update!(metrics: updated)
  end

  def mark_completed!
    update!(
      status: "completed",
      completed_at: Time.current,
    )
  end

  def mark_failed!(error_message)
    update!(
      status: "failed",
      completed_at: Time.current,
      error_message: error_message,
    )
  end

  def duration_seconds
    return nil unless completed_at

    (completed_at - started_at).round(1)
  end

  def compression_efficiency
    m = metrics_hash
    eligible = m["eligible_count"] || 0
    final = m["final_count"] || 0

    return 0 if eligible.zero?

    (final.to_f / eligible * 100).round(2)
  end

  def compression_ratio
    m = metrics_hash
    eligible = m["eligible_count"] || 0
    final = m["final_count"] || 0

    return 0 if final.zero?

    (eligible.to_f / final).round(2)
  end

  def overlap_with_previous_run
    metrics_hash["overlap_with_prev_run"] || 0
  end

  def health_status
    m = metrics_hash
    
    # Check if metrics are within expected ranges
    issues = []
    
    # Compression check
    compression = compression_efficiency
    if compression < 2.0 || compression > 10.0
      issues << "compression_out_of_range"
    end
    
    # Eligible count check
    eligible = m["eligible_count"] || 0
    if eligible < 50 || eligible > 200
      issues << "eligible_count_out_of_range"
    end
    
    # Final count check
    final = m["final_count"] || 0
    if final < 1 || final > 10
      issues << "final_count_out_of_range"
    end
    
    # Overlap check (should be reasonable, not too high or too low)
    overlap = overlap_with_previous_run
    if overlap > 80
      issues << "high_overlap"
    end
    
    # AI cost check
    ai_cost = m["ai_cost"] || 0
    if ai_cost > 10.0 # $10 per run threshold
      issues << "high_ai_cost"
    end
    
    {
      healthy: issues.empty?,
      issues: issues,
      compression_efficiency: compression,
      eligible_count: eligible,
      final_count: final,
      overlap: overlap,
      ai_cost: ai_cost,
    }
  end

  def calculate_metrics!
    ScreenerRuns::MetricsCalculator.call(self)
  end
end
