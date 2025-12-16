# frozen_string_literal: true

module Trading
  # Helper to access trading configuration
  class Config
    def self.dto_enabled?
      config_value("trading", "dto_enabled") == true ||
        ENV["TRADING_DTO_ENABLED"] == "true"
    end

    def self.decision_engine_enabled?
      config_value("trading", "decision_engine", "enabled") == true ||
        ENV["TRADING_DECISION_ENGINE_ENABLED"] == "true"
    end

    def self.llm_enabled?
      config_value("trading", "llm", "enabled") == true ||
        ENV["TRADING_LLM_ENABLED"] == "true"
    end

    def self.current_mode
      config_value("trading", "modes", "current") || "advisory"
    end

    private

    def self.config_value(*keys)
      begin
        config = Rails.application.config_for(:trading)
        keys.reduce(config) { |hash, key| hash&.dig(key.to_s) }
      rescue StandardError
        nil
      end
    end
  end
end
