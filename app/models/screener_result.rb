# frozen_string_literal: true

class ScreenerResult < ApplicationRecord
  belongs_to :instrument
  belongs_to :screener_run, optional: true

  validates :screener_type, presence: true, inclusion: { in: %w[swing longterm] }
  validates :stage, inclusion: { in: %w[screener ranked ai_evaluated final] }, allow_nil: true
  validates :ai_status, inclusion: { in: %w[pending evaluated failed skipped] }, allow_nil: true
  validates :ai_eval_id, uniqueness: true, allow_nil: true
  validates :symbol, presence: true
  validates :score, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :analyzed_at, presence: true

  scope :swing, -> { where(screener_type: "swing") }
  scope :longterm, -> { where(screener_type: "longterm") }
  scope :recent, -> { order(analyzed_at: :desc) }
  scope :by_date, ->(date) { where(analyzed_at: date.beginning_of_day..date.end_of_day) }
  scope :top_scored, ->(limit = 50) { order(score: :desc).limit(limit) }
  scope :today, -> { by_date(Date.current) }
  scope :latest, -> { where(analyzed_at: maximum(:analyzed_at)) }
  scope :by_run, ->(run_id) { where(screener_run_id: run_id) }
  scope :by_stage, ->(stage) { where(stage: stage) }
  scope :ai_evaluated, -> { where(ai_status: "evaluated") }
  scope :ai_pending, -> { where(ai_status: ["pending", nil]) }
  scope :ai_failed, -> { where(ai_status: "failed") }

  def indicators_hash
    return {} if indicators.blank?

    JSON.parse(indicators)
  rescue JSON::ParserError
    {}
  end

  def metadata_hash
    return {} if metadata.blank?

    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end

  def multi_timeframe_hash
    return {} if multi_timeframe.blank?

    JSON.parse(multi_timeframe)
  rescue JSON::ParserError
    {}
  end

  def trade_quality_breakdown_hash
    return {} if trade_quality_breakdown.blank?

    JSON.parse(trade_quality_breakdown)
  rescue JSON::ParserError
    {}
  end

  # Convert to candidate hash format for compatibility with existing views
  def to_candidate_hash
    {
      instrument_id: instrument_id,
      symbol: symbol,
      score: score.to_f,
      base_score: base_score.to_f,
      mtf_score: mtf_score.to_f,
      indicators: indicators_hash,
      metadata: metadata_hash,
      multi_timeframe: multi_timeframe_hash,
      trade_quality_score: trade_quality_score&.to_f,
      trade_quality_breakdown: trade_quality_breakdown_hash,
      ai_confidence: ai_confidence&.to_f,
      ai_risk: ai_risk,
      ai_holding_days: ai_holding_days,
      ai_comment: ai_comment,
      ai_avoid: ai_avoid || false,
    }
  end

  # Get latest results for a screener type
  def self.latest_for(screener_type:, limit: nil)
    latest_analyzed_at = where(screener_type: screener_type).maximum(:analyzed_at)
    return [] unless latest_analyzed_at

    scope = where(screener_type: screener_type, analyzed_at: latest_analyzed_at)
                                          .order(score: :desc)
    scope = scope.limit(limit) if limit
    scope
  end

  # Get or create result for an instrument (upsert)
  def self.upsert_result(attributes)
    analyzed_at = attributes[:analyzed_at] || Time.current
    screener_run_id = attributes[:screener_run_id]
    stage = attributes[:stage] || "screener"

    # Find by run_id + instrument_id if run_id provided, otherwise fallback to old logic
    result = if screener_run_id
               find_or_initialize_by(
                 screener_run_id: screener_run_id,
                 instrument_id: attributes[:instrument_id],
                 screener_type: attributes[:screener_type],
               )
             else
               find_or_initialize_by(
                 instrument_id: attributes[:instrument_id],
                 screener_type: attributes[:screener_type],
                 analyzed_at: analyzed_at.beginning_of_minute, # Round to minute for grouping
               )
             end

    result.assign_attributes(
      symbol: attributes[:symbol],
      score: attributes[:score],
      base_score: attributes[:base_score] || 0,
      mtf_score: attributes[:mtf_score] || 0,
      indicators: attributes[:indicators].to_json,
      metadata: attributes[:metadata].to_json,
      multi_timeframe: attributes[:multi_timeframe].to_json,
      trade_quality_score: attributes[:trade_quality_score],
      trade_quality_breakdown: attributes[:trade_quality_breakdown]&.to_json,
      ai_confidence: attributes[:ai_confidence],
      ai_risk: attributes[:ai_risk],
      ai_holding_days: attributes[:ai_holding_days],
      ai_comment: attributes[:ai_comment],
      ai_avoid: attributes[:ai_avoid] || false,
      screener_run_id: screener_run_id,
      stage: stage,
      ai_status: attributes[:ai_status],
      ai_eval_id: attributes[:ai_eval_id],
      analyzed_at: analyzed_at,
    )

    result.save!
    result
  end
end
