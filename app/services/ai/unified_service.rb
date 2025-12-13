# frozen_string_literal: true

module AI
  # Unified AI service that can use either OpenAI or Ollama
  # Automatically falls back to Ollama if OpenAI is unavailable or configured
  class UnifiedService < ApplicationService
    def self.call(prompt:, provider: nil, model: nil, temperature: nil, max_tokens: nil, cache: true, **options)
      new(
        prompt: prompt,
        provider: provider,
        model: model,
        temperature: temperature,
        max_tokens: max_tokens,
        cache: cache,
        **options,
      ).call
    end

    def initialize(prompt:, provider: nil, model: nil, temperature: nil, max_tokens: nil, cache: true, **options)
      @prompt = prompt
      @provider = provider || determine_provider
      @model = model
      @temperature = temperature
      @max_tokens = max_tokens
      @cache = cache
      @options = options
    end

    def call
      case @provider.to_s.downcase
      when "ollama", "local"
        call_ollama
      when "openai", "open_ai"
        call_openai
      else
        # Auto-detect: try OpenAI first, fallback to Ollama
        result = call_openai
        return result if result[:success]

        Rails.logger.info("[AI::UnifiedService] OpenAI failed, falling back to Ollama")
        call_ollama
      end
    end

    private

    def determine_provider
      # Check config first
      config_provider = AlgoConfig.fetch(%i[ai provider]) || AlgoConfig.fetch(%i[swing_trading ai_ranking provider])
      return config_provider if config_provider.present?

      # Check environment variable
      return ENV["AI_PROVIDER"] if ENV["AI_PROVIDER"].present?

      # Default: auto-detect
      "auto"
    end

    def call_openai
      model = @model || AlgoConfig.fetch(%i[swing_trading ai_ranking model]) || "gpt-4o-mini"
      temperature = @temperature || AlgoConfig.fetch(%i[swing_trading ai_ranking temperature]) || 0.3

      Openai::Service.call(
        prompt: @prompt,
        model: model,
        temperature: temperature,
        max_tokens: @max_tokens,
        cache: @cache,
      )
    rescue StandardError => e
      Rails.logger.error("[AI::UnifiedService] OpenAI call failed: #{e.message}")
      { success: false, error: "OpenAI error: #{e.message}" }
    end

    def call_ollama
      model = @model || AlgoConfig.fetch(%i[ollama model]) || "llama3.2"
      temperature = @temperature || AlgoConfig.fetch(%i[ollama temperature]) || 0.3
      base_url = @options[:base_url] || ENV.fetch("OLLAMA_BASE_URL", nil)

      Ollama::Service.call(
        prompt: @prompt,
        model: model,
        temperature: temperature,
        base_url: base_url,
        cache: @cache,
        timeout: @options[:timeout],
      )
    rescue StandardError => e
      Rails.logger.error("[AI::UnifiedService] Ollama call failed: #{e.message}")
      { success: false, error: "Ollama error: #{e.message}" }
    end
  end
end
