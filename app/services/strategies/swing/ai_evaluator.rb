# frozen_string_literal: true

module Strategies
  module Swing
    class AIEvaluator < ApplicationService
      def self.call(signal)
        new(signal: signal).call
      end

      def initialize(signal:)
        @signal = signal
        @config = AlgoConfig.fetch([:swing_trading, :ai_ranking]) || {}
      end

      def call
        return { success: false, error: 'Invalid signal' } unless @signal.present?
        return { success: false, error: 'AI ranking disabled' } unless @config[:enabled]

        # Build compact prompt
        prompt = build_prompt

        # Call OpenAI
        result = Openai::Service.call(
          prompt: prompt,
          model: @config[:model] || 'gpt-4o-mini',
          temperature: @config[:temperature] || 0.3
        )

        return { success: false, error: result[:error] } unless result[:success]

        # Parse JSON response
        parsed = parse_response(result[:content])
        return { success: false, error: 'Failed to parse response' } unless parsed

        {
          success: true,
          ai_score: parsed[:score],
          ai_confidence: parsed[:confidence],
          ai_summary: parsed[:summary],
          ai_risk: parsed[:risk],
          cached: result[:cached]
        }
      end

      private

      def build_prompt
        <<~PROMPT
          Analyze this swing trading signal and provide JSON response:

          Symbol: #{@signal[:symbol]}
          Direction: #{@signal[:direction]}
          Entry: #{@signal[:entry_price]}
          Stop Loss: #{@signal[:sl]}
          Take Profit: #{@signal[:tp]}
          Risk-Reward: #{@signal[:rr]}
          Confidence: #{@signal[:confidence]}/100
          Holding Days: #{@signal[:holding_days_estimate]}

          Provide JSON:
          {
            "score": 0-100,
            "confidence": 0-100,
            "summary": "brief analysis",
            "risk": "low|medium|high"
          }
        PROMPT
      end

      def parse_response(content)
        return nil unless content

        # Extract JSON (handle markdown code blocks)
        json_text = content.strip
        json_text = json_text.gsub(/```json\s*/, '').gsub(/```\s*$/, '') if json_text.include?('```')

        parsed = JSON.parse(json_text)
        {
          score: parsed['score']&.to_f || 0,
          confidence: parsed['confidence']&.to_f || 0,
          summary: parsed['summary'] || '',
          risk: parsed['risk']&.downcase || 'medium'
        }
      rescue JSON::ParserError => e
        Rails.logger.error("[Strategies::Swing::AIEvaluator] JSON parse error: #{e.message}")
        Rails.logger.debug("[Strategies::Swing::AIEvaluator] Content: #{content}")
        nil
      rescue StandardError => e
        Rails.logger.error("[Strategies::Swing::AIEvaluator] Parse error: #{e.message}")
        nil
      end
    end
  end
end

