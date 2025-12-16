# frozen_string_literal: true

module Trading
  # Audit log for trade recommendations and decisions
  # Tracks: facts, intent, decision path, LLM notes, execution result
  # Critical for debugging drawdowns and understanding trade outcomes
  class AuditLog
    attr_reader :trade_recommendation
    attr_reader :decision_result
    attr_reader :execution_result
    attr_reader :llm_review
    attr_reader :system_context
    attr_reader :logged_at

    def initialize(
      trade_recommendation:,
      decision_result: nil,
      execution_result: nil,
      llm_review: nil,
      system_context: nil,
      logged_at: Time.current
    )
      @trade_recommendation = trade_recommendation
      @decision_result = decision_result
      @execution_result = execution_result
      @llm_review = llm_review
      @system_context = system_context
      @logged_at = logged_at
    end

    # Log decision (after Decision Engine)
    def log_decision(decision_result, system_context: nil, llm_review: nil)
      @decision_result = decision_result
      @system_context = system_context
      @llm_review = llm_review
      @logged_at = Time.current

      persist_log
    end

    # Log execution (after Executor)
    def log_execution(execution_result)
      @execution_result = execution_result
      @logged_at = Time.current

      persist_log
    end

    # Get full audit trail
    def to_hash
      {
        symbol: trade_recommendation.symbol,
        instrument_id: trade_recommendation.instrument_id,
        timeframe: trade_recommendation.timeframe,
        logged_at: logged_at.iso8601,
        facts: extract_facts,
        intent: extract_intent,
        decision_path: extract_decision_path,
        llm_notes: extract_llm_notes,
        execution_result: extract_execution_result,
        lifecycle_state: trade_recommendation.lifecycle.current_state,
        lifecycle_history: trade_recommendation.lifecycle.history,
        system_context: extract_system_context,
      }
    end

    def to_json(*args)
      to_hash.to_json(*args)
    end

    # Persist to storage (Redis cache or database)
    def persist_log
      # Store in Redis cache (keyed by symbol + timestamp)
      cache_key = build_cache_key
      Rails.cache.write(cache_key, to_hash, expires_in: 30.days)

      # Optionally store in database (if AuditLogEntry model exists)
      persist_to_database if defined?(AuditLogEntry)

      self
    end

    # Find logs for a symbol
    def self.find_by_symbol(symbol, limit: 100)
      pattern = "audit_log:#{symbol}:*"
      keys = Rails.cache.respond_to?(:keys) ? Rails.cache.keys(pattern).first(limit) : []

      keys.map do |key|
        hash = Rails.cache.read(key)
        build_from_hash(hash) if hash
      end.compact.sort_by { |log| -log.logged_at.to_i }
    end

    # Find logs for a date range
    def self.find_by_date_range(start_date:, end_date:, limit: 100)
      # Implementation depends on storage backend
      # For Redis, would need to scan keys
      []
    end

    # Build from hash (for retrieval)
    def self.build_from_hash(hash)
      return nil unless hash

      # Reconstruct TradeRecommendation from hash
      recommendation = reconstruct_recommendation(hash)

      new(
        trade_recommendation: recommendation,
        decision_result: hash["decision_result"] || hash[:decision_result],
        execution_result: hash["execution_result"] || hash[:execution_result],
        llm_review: hash["llm_notes"] || hash[:llm_notes],
        system_context: hash["system_context"] || hash[:system_context],
        logged_at: parse_timestamp(hash["logged_at"] || hash[:logged_at]),
      )
    end

    private

    def extract_facts
      {
        symbol: trade_recommendation.facts.symbol,
        instrument_id: trade_recommendation.facts.instrument_id,
        timeframe: trade_recommendation.facts.timeframe,
        indicators: trade_recommendation.facts.indicators_snapshot,
        trend_flags: trade_recommendation.facts.trend_flags,
        momentum_flags: trade_recommendation.facts.momentum_flags,
        screener_score: trade_recommendation.facts.screener_score,
        setup_status: trade_recommendation.facts.setup_status,
        detected_at: trade_recommendation.facts.detected_at.iso8601,
      }
    end

    def extract_intent
      {
        bias: trade_recommendation.intent.bias,
        proposed_entry: trade_recommendation.intent.proposed_entry,
        proposed_sl: trade_recommendation.intent.proposed_sl,
        proposed_targets: trade_recommendation.intent.proposed_targets,
        expected_rr: trade_recommendation.intent.expected_rr,
        sizing_hint: trade_recommendation.intent.sizing_hint,
        strategy_key: trade_recommendation.intent.strategy_key,
      }
    end

    def extract_decision_path
      return [] unless decision_result

      decision_result[:decision_path] || []
    end

    def extract_llm_notes
      return nil unless llm_review && llm_review[:contract]

      contract = llm_review[:contract]
      {
        advisory_level: contract.advisory_level,
        confidence_adjustment: contract.confidence_adjustment,
        notes: contract.notes,
        provider: llm_review[:provider],
      }
    end

    def extract_execution_result
      return nil unless execution_result

      {
        success: execution_result[:success],
        error: execution_result[:error],
        gate: execution_result[:gate],
        order_id: execution_result.dig(:order, :id) || execution_result.dig(:order, "id"),
        lifecycle_state: execution_result[:lifecycle_state],
        dry_run: execution_result[:dry_run] || false,
      }
    end

    def extract_system_context
      return nil unless system_context

      system_context.to_hash
    end

    def build_cache_key
      timestamp = logged_at.to_i
      "audit_log:#{trade_recommendation.symbol}:#{timestamp}"
    end

    def persist_to_database
      return unless defined?(AuditLogEntry)

      AuditLogEntry.create!(
        symbol: trade_recommendation.symbol,
        instrument_id: trade_recommendation.instrument_id,
        timeframe: trade_recommendation.timeframe,
        audit_data: to_hash.to_json,
        logged_at: logged_at,
      )
    rescue StandardError => e
      Rails.logger.error("[Trading::AuditLog] Failed to persist to database: #{e.message}")
    end

    def self.reconstruct_recommendation(hash)
      # This would need to reconstruct TradeRecommendation from hash
      # For now, return nil (would need full implementation)
      nil
    end

    def self.parse_timestamp(timestamp)
      return Time.current unless timestamp

      timestamp.is_a?(Time) ? timestamp : Time.parse(timestamp.to_s)
    rescue StandardError
      Time.current
    end
  end
end
