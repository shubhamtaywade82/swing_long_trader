# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OpenAI::Client, type: :service do
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
      # Set rate limit to exceeded
      today = Date.today.to_s
      Rails.cache.write("openai_calls:#{today}", 50, expires_in: 1.day)

      result = described_class.call(prompt: prompt)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Rate limit exceeded')
    end

    it 'caches responses' do
      # Mock API response
      mock_response = {
        'choices' => [
          {
            'message' => {
              'content' => '{"score": 85, "confidence": 80}'
            }
          }
        ],
        'usage' => {
          'prompt_tokens' => 50,
          'completion_tokens' => 20,
          'total_tokens' => 70
        }
      }

      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 200, body: mock_response.to_json)

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
      mock_response = {
        'choices' => [
          {
            'message' => {
              'content' => '{"score": 85, "confidence": 80, "summary": "Good signal", "risk": "medium"}'
            }
          }
        ],
        'usage' => {
          'prompt_tokens' => 50,
          'completion_tokens' => 20,
          'total_tokens' => 70
        }
      }

      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 200, body: mock_response.to_json)

      result = described_class.call(prompt: prompt)

      expect(result[:success]).to be true
      expect(result[:content]).to include('score')
      expect(result[:usage]).not_to be_nil
    end

    it 'handles non-JSON response gracefully' do
      mock_response = {
        'choices' => [
          {
            'message' => {
              'content' => 'This is not JSON content'
            }
          }
        ],
        'usage' => {
          'prompt_tokens' => 50,
          'completion_tokens' => 20,
          'total_tokens' => 70
        }
      }

      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 200, body: mock_response.to_json)

      result = described_class.call(prompt: prompt)

      # Should still succeed, but content may not be JSON
      expect(result[:success]).to be true
      expect(result[:content]).to eq('This is not JSON content')
    end

    it 'tracks token usage' do
      mock_response = {
        'choices' => [
          {
            'message' => {
              'content' => '{"score": 85}'
            }
          }
        ],
        'usage' => {
          'prompt_tokens' => 100,
          'completion_tokens' => 50,
          'total_tokens' => 150
        }
      }

      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 200, body: mock_response.to_json)

      described_class.call(prompt: prompt)

      today = Date.today.to_s
      tokens = Rails.cache.read("openai_tokens:#{today}")

      expect(tokens).not_to be_nil
      expect(tokens[:prompt]).to eq(100)
      expect(tokens[:completion]).to eq(50)
      expect(tokens[:total]).to eq(150)
    end

    it 'handles API errors gracefully' do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 500, body: 'Internal Server Error')

      result = described_class.call(prompt: prompt)

      expect(result[:success]).to be false
      expect(result[:error]).not_to be_nil
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

