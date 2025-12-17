# frozen_string_literal: true

module Trading
  module Adapters
    # Converts ScreenerResult → TradeFacts
    # Pure data extraction - NO computation, NO entry/SL/TP
    class ScreenerResultToFacts
      def self.call(screener_result)
        new(screener_result).call
      end

      def initialize(screener_result)
        @screener_result = screener_result
      end

      def call
        return nil unless @screener_result

        # Extract indicators snapshot
        indicators = extract_indicators

        # Extract trend flags
        trend_flags = extract_trend_flags(indicators)

        # Extract momentum flags
        momentum_flags = extract_momentum_flags(indicators)

        Trading::TradeFacts.new(
          symbol: @screener_result.symbol,
          instrument_id: @screener_result.instrument_id,
          timeframe: determine_timeframe,
          indicators_snapshot: indicators,
          trend_flags: trend_flags,
          momentum_flags: momentum_flags,
          screener_score: @screener_result.score.to_f,
          setup_status: extract_setup_status,
          detected_at: @screener_result.analyzed_at || Time.current,
        )
      end

      private

      def extract_indicators
        # Get indicators hash from ScreenerResult
        indicators = @screener_result.indicators_hash || {}

        # Handle both swing and longterm formats
        if indicators.key?("weekly_indicators") || indicators.key?(:weekly_indicators)
          # Longterm format: has daily and weekly
          daily = indicators.except("weekly_indicators", :weekly_indicators)
          weekly = indicators["weekly_indicators"] || indicators[:weekly_indicators] || {}
          {
            daily: deep_symbolize_keys(daily),
            weekly: deep_symbolize_keys(weekly),
          }
        else
          # Swing format: all indicators are daily
          deep_symbolize_keys(indicators)
        end
      end

      def extract_trend_flags(indicators)
        flags = []

        # Use daily indicators for trend (or top-level for swing)
        daily_indicators = if indicators.is_a?(Hash) && indicators.key?(:daily)
                            indicators[:daily]
                          else
                            indicators
                          end

        return flags unless daily_indicators.is_a?(Hash)

        # EMA alignment
        if daily_indicators[:ema20] && daily_indicators[:ema50]
          flags << :ema_bullish if daily_indicators[:ema20] > daily_indicators[:ema50]
          flags << :ema_bearish if daily_indicators[:ema20] < daily_indicators[:ema50]
        end

        if daily_indicators[:ema20] && daily_indicators[:ema200]
          flags << :ema200_bullish if daily_indicators[:ema20] > daily_indicators[:ema200]
          flags << :ema200_bearish if daily_indicators[:ema20] < daily_indicators[:ema200]
        end

        # Supertrend
        if daily_indicators[:supertrend]
          st = daily_indicators[:supertrend]
          if st.is_a?(Hash)
            flags << :supertrend_bullish if st[:direction] == :bullish || st[:direction] == "bullish"
            flags << :supertrend_bearish if st[:direction] == :bearish || st[:direction] == "bearish"
          end
        end

        # Overall trend
        flags << :bullish if flags.include?(:ema_bullish) && flags.include?(:supertrend_bullish)
        flags << :bearish if flags.include?(:ema_bearish) && flags.include?(:supertrend_bearish)

        flags.uniq
      end

      def extract_momentum_flags(indicators)
        flags = []

        # Use daily indicators for momentum (or top-level for swing)
        daily_indicators = if indicators.is_a?(Hash) && indicators.key?(:daily)
                            indicators[:daily]
                          else
                            indicators
                          end

        return flags unless daily_indicators.is_a?(Hash)

        # RSI momentum
        if daily_indicators[:rsi]
          rsi = daily_indicators[:rsi].to_f
          flags << :rsi_oversold if rsi < 30
          flags << :rsi_overbought if rsi > 70
          flags << :rsi_bullish if rsi > 50 && rsi < 70
          flags << :rsi_bearish if rsi < 50 && rsi > 30
        end

        # MACD momentum
        if daily_indicators[:macd].is_a?(Array) && daily_indicators[:macd].size >= 2
          macd_line = daily_indicators[:macd][0]
          signal_line = daily_indicators[:macd][1]
          if macd_line && signal_line
            flags << :macd_bullish if macd_line > signal_line
            flags << :macd_bearish if macd_line < signal_line
          end
        end

        # ADX strength
        if daily_indicators[:adx]
          adx = daily_indicators[:adx].to_f
          flags << :adx_strong if adx > 25
          flags << :adx_weak if adx < 20
        end

        flags.uniq
      end

      def determine_timeframe
        # Extract from screener_type
        case @screener_result.screener_type
        when "swing"
          "swing"
        when "longterm"
          "longterm"
        else
          "swing" # Default
        end
      end

      def extract_setup_status
        # Get from metadata
        metadata = @screener_result.metadata_hash || {}
        metadata["setup_status"] || metadata[:setup_status] || @screener_result.setup_status
      end

      def deep_symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(key, value), result|
          new_key = key.is_a?(String) ? key.to_sym : key
          new_value = case value
                     when Hash
                       deep_symbolize_keys(value)
                     when Array
                       value.map { |v| v.is_a?(Hash) ? deep_symbolize_keys(v) : v }
                     else
                       value
                     end
          result[new_key] = new_value
        end
      end
    end
  end
end
