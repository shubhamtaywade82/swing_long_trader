# frozen_string_literal: true

module Strategies
  module Swing
    class AIEvaluator < ApplicationService
      def self.call(signal)
        new(signal: signal).call
      end

      def initialize(signal:)
        @signal = signal
        @config = AlgoConfig.fetch(%i[swing_trading ai_ranking]) || {}
      end

      def call
        return { success: false, error: "Invalid signal" } if @signal.blank?
        return { success: false, error: "AI ranking disabled" } unless @config[:enabled]

        # Build compact prompt
        prompt = build_prompt

        # Call AI service (OpenAI or Ollama based on config)
        result = AI::UnifiedService.call(
          prompt: prompt,
          provider: @config[:provider] || "auto",
          model: @config[:model],
          temperature: @config[:temperature] || 0.3,
        )

        return { success: false, error: result[:error] } unless result[:success]

        # Parse JSON response
        parsed = parse_response(result[:content])
        return { success: false, error: "Failed to parse response" } unless parsed

        {
          success: true,
          ai_score: parsed[:score],
          ai_confidence: parsed[:confidence],
          ai_summary: parsed[:summary],
          ai_risk: parsed[:risk],
          timeframe_alignment: parsed[:timeframe_alignment],
          entry_timing: parsed[:entry_timing],
          cached: result[:cached],
        }
      end

      private

      def build_prompt
        mtf_data = @signal[:metadata]&.dig(:multi_timeframe) || {}
        mtf_summary = build_mtf_summary(mtf_data)

        <<~PROMPT
          Analyze this swing trading signal using multi-timeframe analysis (15m, 1h, 1d, 1w) and provide JSON response:

          Symbol: #{@signal[:symbol]}
          Direction: #{@signal[:direction]}
          Entry: #{@signal[:entry_price]}
          Stop Loss: #{@signal[:sl]}
          Take Profit: #{@signal[:tp]}
          Risk-Reward: #{@signal[:rr]}
          Confidence: #{@signal[:confidence]}/100
          Holding Days: #{@signal[:holding_days_estimate]}

          #{mtf_summary}

          Consider:
          - Multi-timeframe trend alignment (higher timeframes should align)
          - Support/resistance levels from weekly and daily charts
          - Entry timing from 15m and 1h charts
          - Overall structure across all timeframes

          Provide JSON:
          {
            "score": 0-100,
            "confidence": 0-100,
            "summary": "brief multi-timeframe analysis",
            "risk": "low|medium|high",
            "timeframe_alignment": "excellent|good|fair|poor",
            "entry_timing": "optimal|good|fair|poor"
          }
        PROMPT
      end

      def build_mtf_summary(mtf_data)
        return "" if mtf_data.empty?

        summary = "\nMulti-Timeframe Analysis:\n"
        summary += "- MTF Score: #{mtf_data[:score] || 'N/A'}/100\n"

        if mtf_data[:trend_alignment]
          ta = mtf_data[:trend_alignment]
          summary += "- Trend Alignment: #{ta[:aligned] ? 'ALIGNED' : 'NOT ALIGNED'} "
          summary += "(Bullish: #{ta[:bullish_count]}, Bearish: #{ta[:bearish_count]})\n"
        end

        if mtf_data[:momentum_alignment]
          ma = mtf_data[:momentum_alignment]
          summary += "- Momentum Alignment: #{ma[:aligned] ? 'ALIGNED' : 'NOT ALIGNED'} "
          summary += "(Bullish: #{ma[:bullish_count]}, Bearish: #{ma[:bearish_count]})\n"
        end

        if mtf_data[:support_levels]&.any?
          summary += "- Support Levels: #{mtf_data[:support_levels].first(3).map { |s| s.round(2) }.join(', ')}\n"
        end

        if mtf_data[:resistance_levels]&.any?
          summary += "- Resistance Levels: #{mtf_data[:resistance_levels].first(3).map { |r| r.round(2) }.join(', ')}\n"
        end

        if mtf_data[:timeframes_analyzed]&.any?
          summary += "- Timeframes Analyzed: #{mtf_data[:timeframes_analyzed].join(', ')}\n"
        end

        summary
      end

      def parse_response(content)
        return nil unless content

        # Extract JSON (handle markdown code blocks)
        json_text = content.strip
        json_text = json_text.gsub(/```json\s*/, "").gsub(/```\s*$/, "") if json_text.include?("```")

        parsed = JSON.parse(json_text)
        {
          score: parsed["score"]&.to_f || 0,
          confidence: parsed["confidence"]&.to_f || 0,
          summary: parsed["summary"] || "",
          risk: parsed["risk"]&.downcase || "medium",
          timeframe_alignment: parsed["timeframe_alignment"]&.downcase || "fair",
          entry_timing: parsed["entry_timing"]&.downcase || "fair",
        }
      rescue JSON::ParserError => e
        Rails.logger.error("[Strategies::Swing::AIEvaluator] JSON parse error: #{e.message}")
        Rails.logger.debug { "[Strategies::Swing::AIEvaluator] Content: #{content}" }
        nil
      rescue StandardError => e
        Rails.logger.error("[Strategies::Swing::AIEvaluator] Parse error: #{e.message}")
        nil
      end
    end
  end
end
