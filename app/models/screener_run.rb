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
end
