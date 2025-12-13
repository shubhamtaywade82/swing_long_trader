# frozen_string_literal: true

module Ollama
  class Service < ApplicationService
    DEFAULT_BASE_URL = "http://localhost:11434"
    DEFAULT_MODEL = "llama3.2" # Good default for trading analysis
    DEFAULT_TEMPERATURE = 0.3
    DEFAULT_TIMEOUT = 30 # seconds

    # Recommended models for trading:
    # - llama3.2 (3B) - Fast, good for simple analysis
    # - llama3.1 (8B) - Better quality, still fast
    # - mistral (7B) - Good balance
    # - qwen2.5 (7B) - Excellent for structured outputs
    # - deepseek-r1 (1.5B) - Very fast, good for filtering

    def self.call(prompt:, model: nil, temperature: nil, base_url: nil, cache: true, timeout: nil)
      new(
        prompt: prompt,
        model: model,
        temperature: temperature,
        base_url: base_url,
        cache: cache,
        timeout: timeout,
      ).call
    end

    def initialize(prompt:, model: nil, temperature: nil, base_url: nil, cache: true, timeout: nil)
      @prompt = prompt
      @model = model || DEFAULT_MODEL
      @temperature = temperature || DEFAULT_TEMPERATURE
      @base_url = base_url || ENV.fetch("OLLAMA_BASE_URL", DEFAULT_BASE_URL)
      @cache = cache
      @timeout = timeout || DEFAULT_TIMEOUT
    end

    def call
      return { success: false, error: "Ollama not available" } unless ollama_available?

      # Check cache
      if @cache
        cached = fetch_from_cache
        return cached if cached
      end

      # Call Ollama API using gem
      response = call_api
      return { success: false, error: "API call failed" } unless response

      # Track usage
      track_api_call(response)

      # Cache result
      cache_result(response) if @cache

      {
        success: true,
        content: response[:content],
        usage: response[:usage] || {},
        cached: false,
        model: @model,
      }
    rescue StandardError => e
      Rails.logger.error("[Ollama::Service] Error: #{e.message}")
      Rails.logger.debug { "[Ollama::Service] Backtrace: #{e.backtrace.first(5).join("\n")}" }
      { success: false, error: e.message }
    end

    private

    def ollama_available?
      # Check if Ollama is configured and reachable
      return false if @base_url.blank?

      # Quick health check (cache for 5 minutes)
      cache_key = "ollama_health_check:#{@base_url}"
      cached_check = Rails.cache.read(cache_key)
      return cached_check if cached_check

      health_check = perform_health_check
      Rails.cache.write(cache_key, health_check, expires_in: 5.minutes)
      health_check
    rescue StandardError => e
      Rails.logger.warn("[Ollama::Service] Health check failed: #{e.message}")
      false
    end

    def perform_health_check
      require "ollama-ai" unless defined?(Ollama)

      client = Ollama.new(
        credentials: { address: @base_url },
        options: { timeout: 5 },
      )
      client.models.tags
      true
    rescue StandardError
      false
    end

    def call_api
      require "ollama-ai" unless defined?(Ollama)

      client = Ollama.new(
        credentials: { address: @base_url },
        options: { timeout: @timeout },
      )

      # Use chat endpoint (more reliable than generate for structured outputs)
      # The gem returns an array of events, we need the last one with done: true
      events = client.chat(
        {
          model: @model,
          messages: [
            {
              role: "system",
              content: "You are a technical analysis expert specializing in swing trading. Always respond with valid JSON only. Be concise and analytical.",
            },
            {
              role: "user",
              content: @prompt,
            },
          ],
          options: {
            temperature: @temperature,
          },
        },
      )

      # Find the last event (done: true) which contains the full response
      final_event = events.find { |e| e["done"] == true } || events.last
      return nil unless final_event

      # Extract content from message
      content = final_event.dig("message", "content")
      return nil unless content

      # Estimate token usage (rough approximation)
      prompt_tokens = estimate_tokens(@prompt)
      completion_tokens = estimate_tokens(content)

      {
        content: content,
        usage: {
          prompt_tokens: prompt_tokens,
          completion_tokens: completion_tokens,
          total_tokens: prompt_tokens + completion_tokens,
        },
      }
    rescue StandardError => e
      Rails.logger.error("[Ollama::Service] API call failed: #{e.message}")
      Rails.logger.debug { "[Ollama::Service] Error details: #{e.class} - #{e.message}" }
      nil
    end

    def estimate_tokens(text)
      # Rough token estimation: ~4 characters per token for English
      # This is approximate, actual tokenization varies by model
      return 0 if text.blank?

      (text.length / 4.0).ceil
    end

    def cache_key
      "ollama:#{Digest::MD5.hexdigest(@prompt)}:#{@model}"
    end

    def fetch_from_cache
      cached = Rails.cache.read(cache_key)
      return nil unless cached

      {
        success: true,
        content: cached[:content],
        usage: cached[:usage] || {},
        cached: true,
        model: @model,
      }
    end

    def cache_result(response)
      Rails.cache.write(
        cache_key,
        {
          content: response[:content],
          usage: response[:usage],
        },
        expires_in: 24.hours,
      )
    end

    def track_api_call(response)
      today = Time.zone.today.to_s
      cache_key = "ollama_calls:#{today}"
      calls_today = Rails.cache.read(cache_key) || 0
      Rails.cache.write(cache_key, calls_today + 1, expires_in: 1.day)

      # Track token usage
      return unless response[:usage]

      tokens_key = "ollama_tokens:#{today}"
      tokens_today = Rails.cache.read(tokens_key) || { prompt: 0, completion: 0, total: 0 }
      tokens_today[:prompt] += response[:usage][:prompt_tokens] || 0
      tokens_today[:completion] += response[:usage][:completion_tokens] || 0
      tokens_today[:total] += response[:usage][:total_tokens] || 0
      Rails.cache.write(tokens_key, tokens_today, expires_in: 1.day)

      Rails.logger.debug do
        "[Ollama::Service] Call tracked: #{calls_today + 1} calls today, " \
          "#{tokens_today[:total]} total tokens"
      end
    end
  end
end
