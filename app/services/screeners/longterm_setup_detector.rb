# frozen_string_literal: true

module Screeners
  # Determines if a bullish stock is ready for long-term accumulation
  # Long-term is about accumulation zones, not entry points
  class LongtermSetupDetector < ApplicationService
    # Setup statuses for long-term
    ACCUMULATE = "ACCUMULATE"
    WAIT_DIP = "WAIT_DIP"
    WAIT_BREAKOUT = "WAIT_BREAKOUT"
    NOT_READY = "NOT_READY"
    IN_POSITION = "IN_POSITION"

    def self.call(candidate:, daily_series:, weekly_series:, daily_indicators:, weekly_indicators:, mtf_analysis: nil,
                  portfolio: nil)
      new(
        candidate: candidate,
        daily_series: daily_series,
        weekly_series: weekly_series,
        daily_indicators: daily_indicators,
        weekly_indicators: weekly_indicators,
        mtf_analysis: mtf_analysis,
        portfolio: portfolio,
      ).call
    end

    def initialize(candidate:, daily_series:, weekly_series:, daily_indicators:, weekly_indicators:, mtf_analysis: nil, portfolio: nil) # rubocop:disable Lint/MissingSuper
      @candidate = candidate
      @daily_series = daily_series
      @weekly_series = weekly_series
      @daily_indicators = daily_indicators
      @weekly_indicators = weekly_indicators
      @mtf_analysis = mtf_analysis
      @portfolio = portfolio
      @config = AlgoConfig.fetch[:long_term_trading] || {}
    end

    def call
      # Check if already in position
      return { status: IN_POSITION, reason: "Already in position" } if in_position?

      # Must be bullish on weekly timeframe (primary for long-term)
      return { status: NOT_READY, reason: "Not bullish on weekly timeframe" } unless weekly_bullish?

      # Check for valid accumulation setup
      setup_result = detect_accumulation_setup

      {
        status: setup_result[:status],
        reason: setup_result[:reason],
        accumulation_conditions: setup_result[:accumulation_conditions],
        invalidate_if: setup_result[:invalidate_if],
      }
    end

    private

    def in_position?
      return false unless @portfolio

      # Check if instrument has open long-term position in portfolio
      @portfolio.open_long_term_positions.exists?(instrument_id: @candidate[:instrument_id])
    end

    def weekly_bullish?
      # Check weekly supertrend
      return false unless @weekly_indicators[:supertrend]&.dig(:direction) == :bullish

      # Check weekly EMA alignment (safely extract numeric values)
      weekly_ema20 = extract_numeric(@weekly_indicators[:ema20])
      weekly_ema50 = extract_numeric(@weekly_indicators[:ema50])
      return false unless weekly_ema20 && weekly_ema50
      return false unless weekly_ema20.is_a?(Numeric) && weekly_ema50.is_a?(Numeric)
      return false unless weekly_ema20 > weekly_ema50

      true
    end

    def detect_accumulation_setup
      # Safely extract numeric values from indicators (handle Hash/String/nil cases)
      weekly_close = extract_numeric(@weekly_indicators[:latest_close]) || @weekly_series.candles.last&.close
      weekly_ema20 = extract_numeric(@weekly_indicators[:ema20])
      weekly_ema50 = extract_numeric(@weekly_indicators[:ema50])
      weekly_adx = extract_numeric(@weekly_indicators[:adx])
      weekly_atr = extract_numeric(@weekly_indicators[:atr])

      unless weekly_close && weekly_ema20 && weekly_ema50 && weekly_atr
        return { status: NOT_READY,
                 reason: "Missing required indicators" }
      end

      # Ensure all values are numeric before calculation
      # Double-check to prevent Hash/String issues
      weekly_close = ensure_numeric(weekly_close)
      weekly_ema20 = ensure_numeric(weekly_ema20)
      weekly_ema50 = ensure_numeric(weekly_ema50)

      # Validate we have numeric values before proceeding
      unless weekly_close.is_a?(Numeric) && weekly_ema20.is_a?(Numeric) && weekly_ema50.is_a?(Numeric)
        return { status: NOT_READY,
                 reason: "Invalid indicator values (non-numeric)" }
      end

      # Calculate distance from weekly EMA20 (accumulation measure)
      distance_from_weekly_ema20_pct = ((weekly_close - weekly_ema20) / weekly_ema20 * 100).round(2)

      # Check if price is extended (too far above weekly EMA20)
      if distance_from_weekly_ema20_pct > 15
        # Ensure values are numeric for string interpolation
        ema20_val = weekly_ema20.is_a?(Numeric) ? weekly_ema20.round(2) : "N/A"
        ema50_val = weekly_ema50.is_a?(Numeric) ? weekly_ema50.round(2) : "N/A"
        return {
          status: WAIT_DIP,
          reason: "Extended #{distance_from_weekly_ema20_pct}% above weekly EMA20, wait for dip",
          accumulation_conditions: {
            wait_for: "Dip to weekly EMA20 (#{ema20_val}) or 10-15% correction",
            invalidate_if: "Weekly close below EMA50 (#{ema50_val})",
          },
          invalidate_if: "Weekly close below #{ema50_val}",
        }
      end

      # Check if in consolidation (needs breakout)
      if in_weekly_consolidation?
        resistance = find_weekly_resistance_level
        # Ensure resistance is numeric and weekly_close is numeric before comparison
        if resistance && resistance.is_a?(Numeric) && weekly_close.is_a?(Numeric) && weekly_close < resistance
          distance_to_resistance_pct = ((resistance - weekly_close) / weekly_close * 100).round(2)
          if distance_to_resistance_pct < 8
            # Ensure values are numeric for string interpolation
            resistance_val = resistance.is_a?(Numeric) ? resistance.round(2) : "N/A"
            ema20_val = weekly_ema20.is_a?(Numeric) ? weekly_ema20.round(2) : "N/A"
            return {
              status: WAIT_BREAKOUT,
              reason: "Near resistance at #{resistance_val}, wait for breakout",
              accumulation_conditions: {
                wait_for: "Breakout above #{resistance_val} with volume",
                invalidate_if: "Rejection from resistance or weekly close below #{ema20_val}",
              },
              invalidate_if: "Weekly close below #{ema20_val}",
            }
          end
        end
      end

      # Check if weekly ADX is strong enough (ensure numeric)
      weekly_adx = ensure_numeric(weekly_adx) if weekly_adx
      if weekly_adx && weekly_adx.is_a?(Numeric) && weekly_adx < 20
        return {
          status: NOT_READY,
          reason: "Weak weekly trend (ADX #{weekly_adx.round(1)} < 20)",
          accumulation_conditions: {},
          invalidate_if: nil,
        }
      end

      # Check multi-timeframe alignment if available
      if @mtf_analysis && !@mtf_analysis[:trend_alignment][:aligned]
        return {
          status: NOT_READY,
          reason: "Multi-timeframe misalignment",
          accumulation_conditions: {},
          invalidate_if: nil,
        }
      end

      # Check if near weekly EMA20 (good accumulation zone)
      if distance_from_weekly_ema20_pct.between?(-5, 8)
        # ACCUMULATE: Near weekly EMA20, strong trend, good structure
        # Double-check values are numeric for string interpolation
        adx_display = weekly_adx.is_a?(Numeric) ? weekly_adx.round(1) : "N/A"
        ema20_val = weekly_ema20.is_a?(Numeric) ? weekly_ema20.round(2) : "N/A"
        close_val = weekly_close.is_a?(Numeric) ? weekly_close.round(2) : "N/A"
        ema50_val = weekly_ema50.is_a?(Numeric) ? weekly_ema50.round(2) : "N/A"
        return {
          status: ACCUMULATE,
          reason: "In accumulation zone near weekly EMA20 with strong trend (ADX #{adx_display})",
          accumulation_conditions: {
            buy_zone: "#{ema20_val} - #{close_val}",
            trigger: "Price in or near weekly EMA20 zone",
          },
          invalidate_if: "Weekly close below #{ema50_val}",
        }
      end

      # Check if in uptrend but slightly extended (5-15% above weekly EMA20)
      if distance_from_weekly_ema20_pct.between?(8, 15) && weekly_adx && weekly_adx.is_a?(Numeric) && weekly_adx > 25
        # Double-check values are numeric for calculations and string interpolation
        close_val = weekly_close.is_a?(Numeric) ? weekly_close : ensure_numeric(weekly_close)
        ema20_val = weekly_ema20.is_a?(Numeric) ? weekly_ema20 : ensure_numeric(weekly_ema20)
        return nil unless close_val.is_a?(Numeric) && ema20_val.is_a?(Numeric)

        return {
          status: ACCUMULATE,
          reason: "Strong weekly uptrend continuation (ADX #{weekly_adx.round(1)})",
          accumulation_conditions: {
            buy_zone: "#{close_val.round(2)} - #{(close_val * 1.03).round(2)}",
            trigger: "Momentum continuation on weekly",
          },
          invalidate_if: "Weekly close below #{ema20_val.round(2)}",
        }
      end

      # Default: bullish but not ideal setup
      {
        status: NOT_READY,
        reason: "Bullish but accumulation conditions not optimal",
        accumulation_conditions: {},
        invalidate_if: nil,
      }
    end

    def in_weekly_consolidation?
      # Check if price is in a range (high-low spread < 8% over last 10 weekly candles)
      return false if @weekly_series.candles.size < 10

      recent_candles = @weekly_series.candles.last(10)
      highs = recent_candles.map(&:high)
      lows = recent_candles.map(&:low)

      range_high = highs.max
      range_low = lows.min
      range_pct = ((range_high - range_low) / range_low * 100).round(2)

      range_pct < 8
    end

    def find_weekly_resistance_level
      # Find recent swing high (resistance) on weekly
      return nil if @weekly_series.candles.size < 20

      recent_candles = @weekly_series.candles.last(20)
      highs = recent_candles.map(&:high)

      # Find local maxima (swing highs)
      swing_highs = []
      (1..(highs.size - 2)).each do |i|
        swing_highs << highs[i] if highs[i] > highs[i - 1] && highs[i] > highs[i + 1]
      end

      swing_highs.max
    end

    def extract_numeric(value)
      return nil if value.nil?
      return value if value.is_a?(Numeric)
      return nil if value.is_a?(Hash) || value.is_a?(Array)
      return value.to_f if value.is_a?(String) && value.match?(/^-?\d+\.?\d*$/)

      # Try to convert to float (handles BigDecimal, etc.)
      return value.to_f if value.respond_to?(:to_f)

      nil
    rescue StandardError => e
      Rails.logger.warn("[LongtermSetupDetector] Failed to extract numeric from #{value.class}: #{e.message}")
      nil
    end

    def ensure_numeric(value)
      return nil if value.nil?
      return value if value.is_a?(Numeric)
      return nil if value.is_a?(Hash) || value.is_a?(Array)

      # Try to convert
      numeric_value = extract_numeric(value)
      return numeric_value if numeric_value

      # Last resort: try direct conversion
      value.to_f if value.respond_to?(:to_f)
    rescue StandardError => e
      Rails.logger.warn("[LongtermSetupDetector] Failed to ensure numeric from #{value.class}: #{e.message}")
      nil
    end
  end
end
