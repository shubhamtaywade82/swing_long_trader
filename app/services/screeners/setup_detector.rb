# frozen_string_literal: true

module Screeners
  # Determines if a bullish stock is READY to trade, or should WAIT
  # This is the critical decision layer that separates "bullish" from "tradeable"
  class SetupDetector < ApplicationService
    # Setup statuses
    READY = "READY"
    WAIT_PULLBACK = "WAIT_PULLBACK"
    WAIT_BREAKOUT = "WAIT_BREAKOUT"
    NOT_READY = "NOT_READY"
    IN_POSITION = "IN_POSITION"

    def self.call(candidate:, daily_series:, indicators:, mtf_analysis: nil, portfolio: nil)
      new(
        candidate: candidate,
        daily_series: daily_series,
        indicators: indicators,
        mtf_analysis: mtf_analysis,
        portfolio: portfolio,
      ).call
    end

    def initialize(candidate:, daily_series:, indicators:, mtf_analysis: nil, portfolio: nil) # rubocop:disable Lint/MissingSuper
      @candidate = candidate
      @daily_series = daily_series
      @indicators = indicators
      @mtf_analysis = mtf_analysis
      @portfolio = portfolio
      @config = AlgoConfig.fetch[:swing_trading] || {}
    end

    def call
      # Check if already in position
      return { status: IN_POSITION, reason: "Already in position" } if in_position?

      # Must be bullish to be tradeable
      return { status: NOT_READY, reason: "Not bullish" } unless bullish?

      # Check for valid setup
      setup_result = detect_setup

      {
        status: setup_result[:status],
        reason: setup_result[:reason],
        entry_conditions: setup_result[:entry_conditions],
        invalidate_if: setup_result[:invalidate_if],
      }
    end

    private

    def in_position?
      return false unless @portfolio

      # Check if instrument has open position in portfolio
      @portfolio.open_swing_positions.exists?(instrument_id: @candidate[:instrument_id])
    end

    def bullish?
      # Check supertrend
      return false unless @indicators[:supertrend]&.dig(:direction) == :bullish

      # Check EMA alignment
      ema20 = @indicators[:ema20]
      ema50 = @indicators[:ema50]
      return false unless ema20 && ema50 && ema20 > ema50

      true
    end

    def detect_setup
      latest_close = @indicators[:latest_close] || @daily_series.latest_close
      ema20 = @indicators[:ema20]
      ema50 = @indicators[:ema50]
      atr = @indicators[:atr]
      adx = @indicators[:adx]
      rsi = @indicators[:rsi]

      return { status: NOT_READY, reason: "Missing required indicators" } unless latest_close && ema20 && ema50 && atr

      # Calculate distance from EMA20 (pullback measure)
      distance_from_ema20_pct = ((latest_close - ema20) / ema20 * 100).round(2)

      # Check if price is extended (too far above EMA20)
      if distance_from_ema20_pct > 12
        return {
          status: WAIT_PULLBACK,
          reason: "Extended #{distance_from_ema20_pct}% above EMA20, wait for pullback",
          entry_conditions: {
            wait_for: "Pullback to EMA20 (#{ema20.round(2)}) or 8-10% correction",
            invalidate_if: "Daily close below EMA50 (#{ema50.round(2)})",
          },
          invalidate_if: "Daily close below #{ema50.round(2)}",
        }
      end

      # Check if price is in a range/consolidation (needs breakout)
      if in_consolidation?
        resistance = find_resistance_level
        if resistance && latest_close < resistance
          distance_to_resistance_pct = ((resistance - latest_close) / latest_close * 100).round(2)
          if distance_to_resistance_pct < 5
            return {
              status: WAIT_BREAKOUT,
              reason: "Near resistance at #{resistance.round(2)}, wait for breakout",
              entry_conditions: {
                wait_for: "Breakout above #{resistance.round(2)} with volume",
                invalidate_if: "Rejection from resistance or close below #{ema20.round(2)}",
              },
              invalidate_if: "Close below #{ema20.round(2)}",
            }
          end
        end
      end

      # Check if ADX is strong enough (trend strength)
      if adx && adx < 20
        return {
          status: NOT_READY,
          reason: "Weak trend (ADX #{adx.round(1)} < 20)",
          entry_conditions: {},
          invalidate_if: nil,
        }
      end

      # Check if RSI is overbought
      if rsi && rsi > 75
        return {
          status: WAIT_PULLBACK,
          reason: "Overbought (RSI #{rsi.round(1)}), wait for pullback",
          entry_conditions: {
            wait_for: "RSI pullback to 50-60 zone",
            invalidate_if: "RSI stays above 75 for 3+ days",
          },
          invalidate_if: "RSI stays above 75 for 3+ days",
        }
      end

      # Check multi-timeframe alignment if available
      if @mtf_analysis && !@mtf_analysis[:trend_alignment][:aligned]
        return {
          status: NOT_READY,
          reason: "Multi-timeframe misalignment",
          entry_conditions: {},
          invalidate_if: nil,
        }
      end

      # Check if near EMA20 (good entry zone)
      if distance_from_ema20_pct.between?(-2, 5)
        # READY: Near EMA20, strong trend, good structure
        return {
          status: READY,
          reason: "Near EMA20 pullback with strong trend (ADX #{adx&.round(1) || 'N/A'})",
          entry_conditions: {
            entry_zone: "#{ema20.round(2)} - #{latest_close.round(2)}",
            trigger: "Price holds above EMA20 on pullback",
          },
          invalidate_if: "Daily close below #{ema50.round(2)}",
        }
      end

      # Check if in uptrend but slightly extended (2-8% above EMA20)
      if distance_from_ema20_pct.between?(2, 8) && adx && adx > 25
        return {
          status: READY,
          reason: "Strong uptrend continuation (ADX #{adx.round(1)})",
          entry_conditions: {
            entry_zone: "#{latest_close.round(2)} - #{latest_close.round(2) * 1.02}",
            trigger: "Momentum continuation",
          },
          invalidate_if: "Daily close below #{ema20.round(2)}",
        }
      end

      # Default: bullish but not ideal setup
      {
        status: NOT_READY,
        reason: "Bullish but setup conditions not optimal",
        entry_conditions: {},
        invalidate_if: nil,
      }
    end

    def in_consolidation?
      # Check if price is in a range (high-low spread < 5% over last 10 candles)
      return false if @daily_series.candles.size < 10

      # Get recent candles sorted by timestamp (most recent last)
      recent_candles = @daily_series.candles.sort_by(&:timestamp).last(10)
      highs = recent_candles.map(&:high)
      lows = recent_candles.map(&:low)

      range_high = highs.max
      range_low = lows.min
      range_pct = ((range_high - range_low) / range_low * 100).round(2)

      range_pct < 5
    end

    def find_resistance_level
      # Find recent swing high (resistance)
      return nil if @daily_series.candles.size < 20

      # Get recent candles sorted by timestamp (most recent last)
      recent_candles = @daily_series.candles.sort_by(&:timestamp).last(20)
      highs = recent_candles.map(&:high)

      # Find local maxima (swing highs)
      swing_highs = []
      (1..(highs.size - 2)).each do |i|
        swing_highs << highs[i] if highs[i] > highs[i - 1] && highs[i] > highs[i + 1]
      end

      swing_highs.max
    end
  end
end
