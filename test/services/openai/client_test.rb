# frozen_string_literal: true

require 'test_helper'

module OpenAI
  class ClientTest < ActiveSupport::TestCase
    setup do
      @original_key = ENV['OPENAI_API_KEY']
      ENV['OPENAI_API_KEY'] = 'test_key_12345'
      @prompt = 'Test prompt for OpenAI'
    end

    teardown do
      ENV['OPENAI_API_KEY'] = @original_key
      Rails.cache.clear
    end

    test 'should return error when API key not configured' do
      ENV['OPENAI_API_KEY'] = nil

      result = Client.call(prompt: @prompt)

      assert_not result[:success]
      assert_equal 'No API key configured', result[:error]
    end

    test 'should respect rate limit' do
      # Set rate limit to exceeded
      today = Date.today.to_s
      Rails.cache.write("openai_calls:#{today}", 50, expires_in: 1.day)

      result = Client.call(prompt: @prompt)

      assert_not result[:success]
      assert_equal 'Rate limit exceeded', result[:error]
    end

    test 'should cache responses' do
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
      result1 = Client.call(prompt: @prompt, cache: true)
      assert result1[:success]
      assert_not result1[:cached]

      # Second call (should be cached)
      result2 = Client.call(prompt: @prompt, cache: true)
      assert result2[:success]
      assert result2[:cached]
      assert_equal result1[:content], result2[:content]
    end

    test 'should parse JSON response correctly' do
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

      result = Client.call(prompt: @prompt)

      assert result[:success]
      assert_includes result[:content], 'score'
      assert_not_nil result[:usage]
    end

    test 'should handle non-JSON response gracefully' do
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

      result = Client.call(prompt: @prompt)

      # Should still succeed, but content may not be JSON
      assert result[:success]
      assert_equal 'This is not JSON content', result[:content]
    end

    test 'should track token usage' do
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

      Client.call(prompt: @prompt)

      today = Date.today.to_s
      tokens = Rails.cache.read("openai_tokens:#{today}")

      assert_not_nil tokens
      assert_equal 100, tokens[:prompt]
      assert_equal 50, tokens[:completion]
      assert_equal 150, tokens[:total]
    end

    test 'should calculate cost correctly' do
      client = Client.new(prompt: @prompt, model: 'gpt-4o-mini')
      usage = { prompt_tokens: 1000, completion_tokens: 500, total_tokens: 1500 }

      cost = client.send(:calculate_cost, usage, 'gpt-4o-mini')

      # gpt-4o-mini: $0.15/$0.60 per 1M tokens
      # Expected: (1000/1M * 0.15) + (500/1M * 0.60) = 0.00015 + 0.0003 = 0.00045
      assert cost > 0
      assert cost < 0.01 # Should be very small for this token count
    end

    test 'should handle API errors gracefully' do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 500, body: 'Internal Server Error')

      result = Client.call(prompt: @prompt)

      assert_not result[:success]
      assert_not_nil result[:error]
    end
  end
end

