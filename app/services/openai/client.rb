# frozen_string_literal: true

module OpenAI
  class Client < ApplicationService
    MAX_CALLS_PER_DAY = 50
    DEFAULT_MODEL = 'gpt-4o-mini'
    DEFAULT_TEMPERATURE = 0.3
    DEFAULT_MAX_TOKENS = 200

    def self.call(prompt:, model: nil, temperature: nil, max_tokens: nil, cache: true)
      new(
        prompt: prompt,
        model: model,
        temperature: temperature,
        max_tokens: max_tokens,
        cache: cache
      ).call
    end

    def initialize(prompt:, model: nil, temperature: nil, max_tokens: nil, cache: true)
      @prompt = prompt
      @model = model || DEFAULT_MODEL
      @temperature = temperature || DEFAULT_TEMPERATURE
      @max_tokens = max_tokens || DEFAULT_MAX_TOKENS
      @cache = cache
    end

    def call
      return { success: false, error: 'No API key configured' } unless api_key_configured?
      return { success: false, error: 'Rate limit exceeded' } if rate_limit_exceeded?

      # Check cache
      if @cache
        cached = fetch_from_cache
        return cached if cached
      end

      # Call OpenAI API
      response = call_api
      return { success: false, error: 'API call failed' } unless response

      # Track usage
      track_api_call(response)

      # Cache result
      cache_result(response) if @cache

      {
        success: true,
        content: response[:content],
        usage: response[:usage],
        cached: false
      }
    rescue StandardError => e
      Rails.logger.error("[OpenAI::Client] Error: #{e.message}")
      { success: false, error: e.message }
    end

    private

    def api_key_configured?
      ENV['OPENAI_API_KEY'].present?
    end

    def call_api
      require 'ruby/openai' unless defined?(Ruby::OpenAI)

      client = Ruby::OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])

      response = client.chat(
        parameters: {
          model: @model,
          messages: [
            { role: 'system', content: 'You are a technical analysis expert. Always respond with valid JSON only.' },
            { role: 'user', content: @prompt }
          ],
          temperature: @temperature,
          max_tokens: @max_tokens
        }
      )

      content = response.dig('choices', 0, 'message', 'content')
      usage = response['usage'] || {}

      {
        content: content,
        usage: {
          prompt_tokens: usage['prompt_tokens'] || 0,
          completion_tokens: usage['completion_tokens'] || 0,
          total_tokens: usage['total_tokens'] || 0
        }
      }
    rescue StandardError => e
      Rails.logger.error("[OpenAI::Client] API error: #{e.message}")
      nil
    end

    def cache_key
      "openai:#{Digest::MD5.hexdigest(@prompt)}:#{@model}"
    end

    def fetch_from_cache
      cached = Rails.cache.read(cache_key)
      return nil unless cached

      {
        success: true,
        content: cached[:content],
        usage: cached[:usage] || {},
        cached: true
      }
    end

    def cache_result(response)
      Rails.cache.write(
        cache_key,
        {
          content: response[:content],
          usage: response[:usage]
        },
        expires_in: 24.hours
      )
    end

    def rate_limit_exceeded?
      today = Date.today.to_s
      cache_key = "openai_calls:#{today}"
      calls_today = Rails.cache.read(cache_key) || 0
      calls_today >= MAX_CALLS_PER_DAY
    end

    def track_api_call(response)
      today = Date.today.to_s
      cache_key = "openai_calls:#{today}"
      calls_today = Rails.cache.read(cache_key) || 0
      Rails.cache.write(cache_key, calls_today + 1, expires_in: 1.day)

      # Track token usage
      if response[:usage]
        tokens_key = "openai_tokens:#{today}"
        tokens_today = Rails.cache.read(tokens_key) || { prompt: 0, completion: 0, total: 0 }
        tokens_today[:prompt] += response[:usage][:prompt_tokens] || 0
        tokens_today[:completion] += response[:usage][:completion_tokens] || 0
        tokens_today[:total] += response[:usage][:total_tokens] || 0
        Rails.cache.write(tokens_key, tokens_today, expires_in: 1.day)

        # Calculate and track cost
        cost = calculate_cost(response[:usage], @model)
        if cost > 0
          cost_key = "openai_cost:#{today}"
          cost_today = Rails.cache.read(cost_key) || 0.0
          Rails.cache.write(cost_key, cost_today + cost, expires_in: 1.day)

          # Track in metrics
          Metrics::Tracker.track_openai_cost(cost) if defined?(Metrics::Tracker)
        end
      end
    end

    def calculate_cost(usage, model)
      # Pricing per 1M tokens (as of 2024)
      # gpt-4o-mini: $0.15/$0.60 (input/output)
      # gpt-4o: $2.50/$10.00 (input/output)
      # gpt-4-turbo: $10.00/$30.00 (input/output)
      pricing = {
        'gpt-4o-mini' => { input: 0.15, output: 0.60 },
        'gpt-4o' => { input: 2.50, output: 10.00 },
        'gpt-4-turbo' => { input: 10.00, output: 30.00 },
        'gpt-3.5-turbo' => { input: 0.50, output: 1.50 }
      }

      model_pricing = pricing[model] || pricing['gpt-4o-mini']
      prompt_tokens = usage[:prompt_tokens] || 0
      completion_tokens = usage[:completion_tokens] || 0

      input_cost = (prompt_tokens / 1_000_000.0) * model_pricing[:input]
      output_cost = (completion_tokens / 1_000_000.0) * model_pricing[:output]

      (input_cost + output_cost).round(6)
    end
  end
end

