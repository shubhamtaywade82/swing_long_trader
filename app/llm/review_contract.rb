# frozen_string_literal: true

require "json"

module LLM
  # Strict contract for LLM review output
  # LLM can ONLY provide advisory information, NEVER approve/reject
  class ReviewContract
    # Advisory levels
    ADVISORY_INFO = "info" # Informational note, no action needed
    ADVISORY_WARNING = "warning" # Warning but trade can proceed
    ADVISORY_BLOCK_AUTO = "block_auto" # Block automated execution, require manual review

    attr_reader :advisory_level
    attr_reader :confidence_adjustment # Integer: -10 to +10
    attr_reader :notes # String: Explanation

    def initialize(advisory_level:, confidence_adjustment: 0, notes: "")
      @advisory_level = validate_advisory_level(advisory_level)
      @confidence_adjustment = clamp_confidence_adjustment(confidence_adjustment)
      @notes = notes.to_s
    end

    def info?
      advisory_level == ADVISORY_INFO
    end

    def warning?
      advisory_level == ADVISORY_WARNING
    end

    def block_auto?
      advisory_level == ADVISORY_BLOCK_AUTO
    end

    def to_hash
      {
        advisory_level: advisory_level,
        confidence_adjustment: confidence_adjustment,
        notes: notes,
      }
    end

    # Parse from LLM response (with fallback)
    def self.parse(response_content)
      return default_contract unless response_content.present?

      # Extract JSON from response (handle markdown code blocks)
      json_match = response_content.match(/```json\s*(\{.*?\})\s*```/m) ||
                   response_content.match(/(\{.*\})/m)

      return default_contract unless json_match

      parsed = JSON.parse(json_match[1])
      build_from_parsed(parsed)
    rescue JSON::ParserError => e
      Rails.logger.warn("[LLM::ReviewContract] Failed to parse JSON: #{e.message}")
      default_contract
    end

    # Build from parsed hash (with validation)
    def self.build_from_parsed(parsed)
      advisory_level = parsed["advisory_level"] || parsed[:advisory_level] || ADVISORY_INFO
      confidence_adjustment = parsed["confidence_adjustment"] || parsed[:confidence_adjustment] || 0
      notes = parsed["notes"] || parsed[:notes] || ""

      new(
        advisory_level: advisory_level,
        confidence_adjustment: confidence_adjustment,
        notes: notes,
      )
    rescue StandardError => e
      Rails.logger.warn("[LLM::ReviewContract] Failed to build from parsed: #{e.message}")
      default_contract
    end

    # Default contract (when LLM fails or unavailable)
    def self.default_contract
      new(
        advisory_level: ADVISORY_INFO,
        confidence_adjustment: 0,
        notes: "LLM review unavailable - using deterministic decision",
      )
    end

    private

    def validate_advisory_level(level)
      level_str = level.to_s.downcase
      valid_levels = [ADVISORY_INFO, ADVISORY_WARNING, ADVISORY_BLOCK_AUTO]

      if valid_levels.include?(level_str)
        level_str
      else
        Rails.logger.warn("[LLM::ReviewContract] Invalid advisory_level: #{level}, defaulting to info")
        ADVISORY_INFO
      end
    end

    def clamp_confidence_adjustment(adjustment)
      adjustment_int = adjustment.to_i
      [[-10, adjustment_int].max, 10].min
    end
  end
end
