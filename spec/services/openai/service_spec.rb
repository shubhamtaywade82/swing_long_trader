# frozen_string_literal: true

require "rails_helper"

RSpec.describe Openai::Service, type: :service do
  let(:prompt) { "Test prompt for OpenAI" }
  let(:original_key) { ENV.fetch("OPENAI_API_KEY", nil) }

  before do
    ENV["OPENAI_API_KEY"] = "test_key_12345"
  end

  after do
    ENV["OPENAI_API_KEY"] = original_key
    Rails.cache.clear
  end

  describe ".call" do
    it "returns error when API key not configured" do
      ENV["OPENAI_API_KEY"] = nil

      result = described_class.call(prompt: prompt)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("No API key configured")
    end

    it "respects rate limit" do
      # Mock cache to return rate limit exceeded since cache is disabled in test env
      today = Time.zone.today.to_s
      allow(Rails.cache).to receive(:read).with("openai_calls:#{today}").and_return(50)

      result = described_class.call(prompt: prompt)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Rate limit exceeded")
    end

    it "caches responses" do
      # Mock API response
      mock_api_response = {
        content: '{"score": 85, "confidence": 80}',
        usage: {
          prompt_tokens: 50,
          completion_tokens: 20,
          total_tokens: 70,
        },
      }

      # Mock cache to simulate real caching behavior since test env uses null_store
      cache_store = {}
      allow(Rails.cache).to receive(:read) do |key|
        cache_store[key]
      end
      allow(Rails.cache).to receive(:write) do |key, value, _options = {}|
        cache_store[key] = value
      end

      # Stub call_api method on service instances
      allow_any_instance_of(described_class).to receive(:call_api).and_return(mock_api_response)

      # First call
      result1 = described_class.call(prompt: prompt, cache: true)
      expect(result1[:success]).to be true
      expect(result1[:cached]).to be false

      # Second call (should be cached)
      result2 = described_class.call(prompt: prompt, cache: true)
      expect(result2[:success]).to be true
      expect(result2[:cached]).to be true
      expect(result2[:content]).to eq(result1[:content])
    end

    it "parses JSON response correctly" do
      mock_api_response = {
        content: '{"score": 85, "confidence": 80, "summary": "Good signal", "risk": "medium"}',
        usage: {
          prompt_tokens: 50,
          completion_tokens: 20,
          total_tokens: 70,
        },
      }

      # Stub call_api method on service instances
      allow_any_instance_of(described_class).to receive(:call_api).and_return(mock_api_response)

      result = described_class.call(prompt: prompt)

      expect(result[:success]).to be true
      expect(result[:content]).to include("score")
      expect(result[:usage]).not_to be_nil
    end

    it "handles non-JSON response gracefully" do
      mock_api_response = {
        content: "This is not JSON content",
        usage: {
          prompt_tokens: 50,
          completion_tokens: 20,
          total_tokens: 70,
        },
      }

      # Stub call_api method on service instances
      allow_any_instance_of(described_class).to receive(:call_api).and_return(mock_api_response)

      result = described_class.call(prompt: prompt)

      # Should still succeed, but content may not be JSON
      expect(result[:success]).to be true
      expect(result[:content]).to eq("This is not JSON content")
    end

    it "tracks token usage" do
      mock_api_response = {
        content: '{"score": 85}',
        usage: {
          prompt_tokens: 100,
          completion_tokens: 50,
          total_tokens: 150,
        },
      }

      # Mock cache to simulate real caching behavior since test env uses null_store
      cache_store = {}
      allow(Rails.cache).to receive(:read) do |key|
        cache_store[key]
      end
      allow(Rails.cache).to receive(:write) do |key, value, _options = {}|
        cache_store[key] = value
      end

      # Stub call_api method on service instances
      allow_any_instance_of(described_class).to receive(:call_api).and_return(mock_api_response)

      described_class.call(prompt: prompt)

      today = Time.zone.today.to_s
      tokens = cache_store["openai_tokens:#{today}"]

      expect(tokens).not_to be_nil
      expect(tokens[:prompt]).to eq(100)
      expect(tokens[:completion]).to eq(50)
      expect(tokens[:total]).to eq(150)
    end

    it "handles API errors gracefully" do
      # Stub call_api to return nil (simulating API failure)
      allow_any_instance_of(described_class).to receive(:call_api).and_return(nil)

      result = described_class.call(prompt: prompt)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("API call failed")
    end
  end

  describe "#calculate_cost" do
    it "calculates cost correctly" do
      client = described_class.new(prompt: prompt, model: "gpt-4o-mini")
      usage = { prompt_tokens: 1000, completion_tokens: 500, total_tokens: 1500 }

      cost = client.send(:calculate_cost, usage, "gpt-4o-mini")

      # gpt-4o-mini: $0.15/$0.60 per 1M tokens
      # Expected: (1000/1M * 0.15) + (500/1M * 0.60) = 0.00015 + 0.0003 = 0.00045
      expect(cost).to be > 0
      expect(cost).to be < 0.01 # Should be very small for this token count
    end

    it "calculates cost for different models" do
      client = described_class.new(prompt: prompt, model: "gpt-4o")
      usage = { prompt_tokens: 1000, completion_tokens: 500, total_tokens: 1500 }

      cost = client.send(:calculate_cost, usage, "gpt-4o")

      expect(cost).to be > 0
    end

    it "handles missing usage data" do
      client = described_class.new(prompt: prompt)
      usage = {}

      cost = client.send(:calculate_cost, usage, "gpt-4o-mini")

      expect(cost).to eq(0)
    end
  end

  describe "#rate_limit_exceeded?" do
    it "checks rate limit correctly" do
      today = Time.zone.today.to_s
      cache_store = {}
      allow(Rails.cache).to receive(:read) do |key|
        cache_store[key]
      end
      allow(Rails.cache).to receive(:write) do |key, value, _options|
        cache_store[key] = value
      end

      cache_store["openai_calls:#{today}"] = 49
      client = described_class.new(prompt: prompt)

      result = client.send(:rate_limit_exceeded?)
      expect(result).to be false

      cache_store["openai_calls:#{today}"] = 50
      result = client.send(:rate_limit_exceeded?)
      expect(result).to be true
    end
  end

  describe "#track_api_call" do
    it "tracks calls and tokens" do
      cache_store = {}
      allow(Rails.cache).to receive(:read) do |key|
        cache_store[key]
      end
      allow(Rails.cache).to receive(:write) do |key, value, _options|
        cache_store[key] = value
      end

      client = described_class.new(prompt: prompt)
      response = {
        content: "Test response",
        usage: {
          prompt_tokens: 100,
          completion_tokens: 50,
          total_tokens: 150,
        },
      }

      client.send(:track_api_call, response)

      today = Time.zone.today.to_s
      expect(cache_store["openai_calls:#{today}"]).to eq(1)
      expect(cache_store["openai_tokens:#{today}"]).to be_present
    end

    it "handles missing usage gracefully" do
      cache_store = {}
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }
      allow(Rails.cache).to receive(:write) { |key, value, _options| cache_store[key] = value }

      client = described_class.new(prompt: prompt)
      response = { content: "Test response", usage: nil }

      expect { client.send(:track_api_call, response) }.not_to raise_error
    end
  end

  describe "#check_cost_thresholds" do
    it "checks daily cost threshold" do
      cache_store = {}
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }
      allow(Rails.cache).to receive(:write) { |key, value, _options| cache_store[key] = value }
      allow(AlgoConfig).to receive(:fetch).and_return({
        openai: {
          cost_monitoring: {
            enabled: true,
            daily_threshold: 10.0,
          },
        },
      })
      allow(TelegramNotifier).to receive(:send_error_alert)

      client = described_class.new(prompt: prompt)
      client.send(:check_cost_thresholds, 15.0, Time.zone.today.to_s)

      expect(TelegramNotifier).to have_received(:send_error_alert)
    end
  end

  describe "error handling" do
    it "handles API exceptions" do
      allow_any_instance_of(described_class).to receive(:call_api).and_raise(StandardError, "API error")
      allow(Rails.logger).to receive(:error)

      result = described_class.call(prompt: prompt)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("API error")
      expect(Rails.logger).to have_received(:error)
    end
  end

  describe "#fetch_from_cache" do
    it "returns cached response if available" do
      cache_store = {
        "openai:#{Digest::MD5.hexdigest(prompt)}:gpt-4o-mini" => {
          content: "Cached response",
          usage: { total_tokens: 100 },
        },
      }
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }

      client = described_class.new(prompt: prompt, cache: true)
      cached = client.send(:fetch_from_cache)

      expect(cached).to be_present
      expect(cached[:success]).to be true
      expect(cached[:content]).to eq("Cached response")
      expect(cached[:cached]).to be true
    end

    it "returns nil if no cache" do
      cache_store = {}
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }

      client = described_class.new(prompt: prompt, cache: true)
      cached = client.send(:fetch_from_cache)

      expect(cached).to be_nil
    end
  end

  describe "#cache_result" do
    it "caches response with correct key" do
      cache_store = {}
      allow(Rails.cache).to receive(:write) { |key, value, _options| cache_store[key] = value }

      client = described_class.new(prompt: prompt, cache: true)
      response = { content: "Test response", usage: { total_tokens: 100 } }
      client.send(:cache_result, response)

      expected_key = "openai:#{Digest::MD5.hexdigest(prompt)}:gpt-4o-mini"
      expect(cache_store[expected_key]).to eq(response)
    end
  end

  describe "#call_api" do
    it "handles API response with missing usage data" do
      mock_response = double("response",
                             dig: "Test content",
                             "[]" => {})
      allow(mock_response).to receive(:dig).with("choices", 0, "message", "content").and_return("Test content")
      allow(mock_response).to receive(:[]).with("usage").and_return(nil)

      client = described_class.new(prompt: prompt)
      allow(Ruby::OpenAI::Client).to receive(:new).and_return(double("client", chat: mock_response))

      result = client.send(:call_api)

      expect(result).to be_present
      expect(result[:content]).to eq("Test content")
      expect(result[:usage][:total_tokens]).to eq(0)
    end

    it "handles API exceptions" do
      allow(Ruby::OpenAI::Client).to receive(:new).and_raise(StandardError, "API connection error")
      allow(Rails.logger).to receive(:error)

      client = described_class.new(prompt: prompt)
      result = client.send(:call_api)

      expect(result).to be_nil
      expect(Rails.logger).to have_received(:error).with(/API error/)
    end
  end

  describe "with cache disabled" do
    it "does not check cache when cache is false" do
      cache_store = {}
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }
      allow_any_instance_of(described_class).to receive(:call_api).and_return({
        content: "Response",
        usage: { total_tokens: 100 },
      })

      result = described_class.call(prompt: prompt, cache: false)

      expect(result[:success]).to be true
      expect(Rails.cache).not_to have_received(:read)
    end

    it "does not cache result when cache is false" do
      cache_store = {}
      allow(Rails.cache).to receive(:write) { |key, value, _options| cache_store[key] = value }
      allow_any_instance_of(described_class).to receive(:call_api).and_return({
        content: "Response",
        usage: { total_tokens: 100 },
      })

      described_class.call(prompt: prompt, cache: false)

      expect(cache_store).to be_empty
    end
  end

  describe "with custom parameters" do
    it "uses custom model" do
      allow_any_instance_of(described_class).to receive(:call_api).and_return({
        content: "Response",
        usage: { total_tokens: 100 },
      })

      result = described_class.call(prompt: prompt, model: "gpt-4o")

      expect(result[:success]).to be true
    end

    it "uses custom temperature" do
      allow_any_instance_of(described_class).to receive(:call_api).and_return({
        content: "Response",
        usage: { total_tokens: 100 },
      })

      result = described_class.call(prompt: prompt, temperature: 0.5)

      expect(result[:success]).to be true
    end

    it "uses custom max_tokens" do
      allow_any_instance_of(described_class).to receive(:call_api).and_return({
        content: "Response",
        usage: { total_tokens: 100 },
      })

      result = described_class.call(prompt: prompt, max_tokens: 500)

      expect(result[:success]).to be true
    end
  end
end
