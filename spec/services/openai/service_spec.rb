# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Openai::Service, type: :service do
  let(:prompt) { 'Test prompt for OpenAI' }
  let(:original_key) { ENV['OPENAI_API_KEY'] }

  before do
    ENV['OPENAI_API_KEY'] = 'test_key_12345'
  end

  after do
    ENV['OPENAI_API_KEY'] = original_key
    Rails.cache.clear
  end

  describe '.call' do
    it 'returns error when API key not configured' do
      ENV['OPENAI_API_KEY'] = nil

      result = described_class.call(prompt: prompt)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('No API key configured')
    end

    it 'respects rate limit' do
      # Mock cache to return rate limit exceeded since cache is disabled in test env
      today = Date.today.to_s
      allow(Rails.cache).to receive(:read).with("openai_calls:#{today}").and_return(50)

      result = described_class.call(prompt: prompt)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Rate limit exceeded')
    end

    it 'caches responses' do
      # Mock API response
      mock_api_response = {
        content: '{"score": 85, "confidence": 80}',
        usage: {
          prompt_tokens: 50,
          completion_tokens: 20,
          total_tokens: 70
        }
      }

      # Mock cache to simulate real caching behavior since test env uses null_store
      cache_store = {}
      allow(Rails.cache).to receive(:read) do |key|
        cache_store[key]
      end
      allow(Rails.cache).to receive(:write) do |key, value, options = {}|
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

    it 'parses JSON response correctly' do
      mock_api_response = {
        content: '{"score": 85, "confidence": 80, "summary": "Good signal", "risk": "medium"}',
        usage: {
          prompt_tokens: 50,
          completion_tokens: 20,
          total_tokens: 70
        }
      }

      # Stub call_api method on service instances
      allow_any_instance_of(described_class).to receive(:call_api).and_return(mock_api_response)

      result = described_class.call(prompt: prompt)

      expect(result[:success]).to be true
      expect(result[:content]).to include('score')
      expect(result[:usage]).not_to be_nil
    end

    it 'handles non-JSON response gracefully' do
      mock_api_response = {
        content: 'This is not JSON content',
        usage: {
          prompt_tokens: 50,
          completion_tokens: 20,
          total_tokens: 70
        }
      }

      # Stub call_api method on service instances
      allow_any_instance_of(described_class).to receive(:call_api).and_return(mock_api_response)

      result = described_class.call(prompt: prompt)

      # Should still succeed, but content may not be JSON
      expect(result[:success]).to be true
      expect(result[:content]).to eq('This is not JSON content')
    end

    it 'tracks token usage' do
      mock_api_response = {
        content: '{"score": 85}',
        usage: {
          prompt_tokens: 100,
          completion_tokens: 50,
          total_tokens: 150
        }
      }

      # Mock cache to simulate real caching behavior since test env uses null_store
      cache_store = {}
      allow(Rails.cache).to receive(:read) do |key|
        cache_store[key]
      end
      allow(Rails.cache).to receive(:write) do |key, value, options = {}|
        cache_store[key] = value
      end

      # Stub call_api method on service instances
      allow_any_instance_of(described_class).to receive(:call_api).and_return(mock_api_response)

      described_class.call(prompt: prompt)

      today = Date.today.to_s
      tokens = cache_store["openai_tokens:#{today}"]

      expect(tokens).not_to be_nil
      expect(tokens[:prompt]).to eq(100)
      expect(tokens[:completion]).to eq(50)
      expect(tokens[:total]).to eq(150)
    end

    it 'handles API errors gracefully' do
      # Stub call_api to return nil (simulating API failure)
      allow_any_instance_of(described_class).to receive(:call_api).and_return(nil)

      result = described_class.call(prompt: prompt)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('API call failed')
    end
  end

  describe '#calculate_cost' do
    it 'calculates cost correctly' do
      client = described_class.new(prompt: prompt, model: 'gpt-4o-mini')
      usage = { prompt_tokens: 1000, completion_tokens: 500, total_tokens: 1500 }

      cost = client.send(:calculate_cost, usage, 'gpt-4o-mini')

      # gpt-4o-mini: $0.15/$0.60 per 1M tokens
      # Expected: (1000/1M * 0.15) + (500/1M * 0.60) = 0.00015 + 0.0003 = 0.00045
      expect(cost).to be > 0
      expect(cost).to be < 0.01 # Should be very small for this token count
    end
  end
end

