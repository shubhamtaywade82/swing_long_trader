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

  # CRITICAL RULE: No ScreenerResult without screener_run_id (enforced in production)
  validate :must_have_screener_run_id, if: -> { Rails.env.production? }

  def must_have_screener_run_id
    return if screener_run_id.present?

    errors.add(:screener_run_id, "is required - no ScreenerResult may exist without run isolation")
  end

  scope :swing, -> { where(screener_type: "swing") }
  scope :longterm, -> { where(screener_type: "longterm") }
  scope :recent, -> { order(analyzed_at: :desc) }
  scope :by_date, ->(date) { where(analyzed_at: date.all_day) }
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
    indicators = deep_symbolize_keys(indicators_hash)
    metadata = deep_symbolize_keys(metadata_hash)

    # Split indicators into daily_indicators and weekly_indicators
    # The stored format for longterm screener has daily indicators at top level and weekly_indicators nested
    # For swing screener, indicators might be structured differently
    if indicators.key?(:daily_indicators) && indicators.key?(:weekly_indicators)
      # Already split format (shouldn't happen in stored data but handle gracefully)
      daily_indicators = indicators[:daily_indicators] || {}
      weekly_indicators = indicators[:weekly_indicators] || {}
    elsif indicators.key?(:weekly_indicators)
      # Longterm format: daily at top level, weekly nested
      weekly_indicators = indicators.delete(:weekly_indicators) || {}
      daily_indicators = indicators.dup # Remaining keys are daily indicators
    else
      # Swing format or unknown: treat all as daily indicators
      daily_indicators = indicators
      weekly_indicators = {}
    end

    {
      instrument_id: instrument_id,
      symbol: symbol,
      score: score.to_f,
      base_score: base_score.to_f,
      mtf_score: mtf_score.to_f,
      daily_indicators: daily_indicators,
      weekly_indicators: weekly_indicators,
      indicators: daily_indicators.merge(weekly_indicators: weekly_indicators), # Keep for backward compatibility
      metadata: metadata,
      multi_timeframe: deep_symbolize_keys(multi_timeframe_hash),
      trade_quality_score: trade_quality_score&.to_f,
      trade_quality_breakdown: deep_symbolize_keys(trade_quality_breakdown_hash),
      ai_confidence: ai_confidence&.to_f,
      ai_stage: ai_stage,
      ai_momentum_trend: ai_momentum_trend,
      ai_price_position: ai_price_position,
      ai_entry_timing: ai_entry_timing,
      ai_continuation_bias: ai_continuation_bias,
      ai_holding_days: ai_holding_days,
      ai_primary_risk: ai_primary_risk,
      ai_invalidate_if: ai_invalidate_if,
      # Legacy fields
      ai_risk: ai_risk,
      ai_comment: ai_comment,
      ai_avoid: ai_avoid || false,
      # Extract setup_status and trade_plan/accumulation_plan from metadata
      setup_status: metadata[:setup_status],
      setup_reason: metadata[:setup_reason],
      invalidate_if: metadata[:invalidate_if],
      entry_conditions: metadata[:entry_conditions],
      accumulation_conditions: metadata[:accumulation_conditions],
      trade_plan: metadata[:trade_plan], # For swing
      accumulation_plan: metadata[:accumulation_plan], # For long-term
      recommendation: metadata[:recommendation],
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
      ai_stage: attributes[:ai_stage],
      ai_momentum_trend: attributes[:ai_momentum_trend],
      ai_price_position: attributes[:ai_price_position],
      ai_entry_timing: attributes[:ai_entry_timing],
      ai_continuation_bias: attributes[:ai_continuation_bias],
      ai_holding_days: attributes[:ai_holding_days],
      ai_primary_risk: attributes[:ai_primary_risk],
      ai_invalidate_if: attributes[:ai_invalidate_if],
      # Legacy fields
      ai_risk: attributes[:ai_risk],
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

  # Convert to TradeRecommendation (if DTO feature flag enabled)
  def to_trade_recommendation(portfolio: nil)
    return nil unless Trading::Config.dto_enabled?

    Trading::Adapters::ScreenerResultToRecommendation.call(self, portfolio: portfolio)
  end

  private

  def deep_symbolize_keys(hash)
    return hash unless hash.is_a?(Hash)

    hash.each_with_object({}) do |(key, value), result|
      new_key = key.is_a?(String) ? key.to_sym : key
      new_value = case value
                  when Hash
                    deep_symbolize_keys(value)
                  when Array
                    value.map { |v| v.is_a?(Hash) ? deep_symbolize_keys(v) : v }
                  else
                    value
                  end
      result[new_key] = new_value
    end
  end
end
