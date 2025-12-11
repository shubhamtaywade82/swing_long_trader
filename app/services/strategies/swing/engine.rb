# frozen_string_literal: true

module Strategies
  module Swing
    class Engine < ApplicationService
      def self.call(instrument:, daily_series:, weekly_series: nil, config: {})
        new(instrument: instrument, daily_series: daily_series, weekly_series: weekly_series, config: config).call
      end

      def initialize(instrument:, daily_series:, weekly_series: nil, config: {})
        @instrument = instrument
        @daily_series = daily_series
        @weekly_series = weekly_series
        @config = config || AlgoConfig.fetch([:swing_trading, :strategy]) || {}
      end

      def call
        # Validate inputs
        return { success: false, error: 'Invalid instrument' } unless @instrument.present?
        return { success: false, error: 'Insufficient daily candles' } unless @daily_series&.candles&.size.to_i >= 50

        # Check entry conditions
        entry_check = check_entry_conditions
        return { success: false, error: entry_check[:error] } unless entry_check[:allowed]

        # Validate SMC structure (optional)
        smc_validation = validate_smc_structure
        if smc_validation && !smc_validation[:valid]
          return { success: false, error: "SMC validation failed: #{smc_validation[:reasons].join(', ')}" }
        end

        # Build signal
        signal = SignalBuilder.call(
          instrument: @instrument,
          daily_series: @daily_series,
          weekly_series: @weekly_series,
          config: @config
        )

        return { success: false, error: 'Signal generation failed' } unless signal

        # Validate signal meets minimum requirements
        min_confidence = @config[:min_confidence] || 0.7
        if signal[:confidence] < (min_confidence * 100)
          return { success: false, error: "Confidence too low: #{signal[:confidence]} < #{min_confidence * 100}" }
        end

        metadata = {
          evaluated_at: Time.current,
          candles_analyzed: @daily_series.candles.size,
          weekly_available: @weekly_series.present?
        }

        # Add SMC validation to metadata if available
        metadata[:smc_validation] = smc_validation if smc_validation

        {
          success: true,
          signal: signal,
          metadata: metadata
        }
      end

      private

      def check_entry_conditions
        entry_config = @config[:entry_conditions] || {}

        # Check trend alignment requirement
        if entry_config[:require_trend_alignment]
          trend_check = check_trend_alignment
          return { allowed: false, error: 'Trend alignment failed' } unless trend_check
        end

        # Check volume confirmation
        if entry_config[:require_volume_confirmation]
          volume_check = check_volume_confirmation(entry_config[:min_volume_spike] || 1.5)
          return { allowed: false, error: 'Volume confirmation failed' } unless volume_check
        end

        { allowed: true }
      end

      def check_trend_alignment
        indicators = calculate_indicators

        # Check EMA alignment
        trend_filters = @config[:trend_filters] || {}
        if trend_filters[:use_ema20] && trend_filters[:use_ema50]
          return false unless indicators[:ema20] && indicators[:ema50]
          return false unless indicators[:ema20] > indicators[:ema50]
        end

        if trend_filters[:use_ema200]
          return false unless indicators[:ema20] && indicators[:ema200]
          return false unless indicators[:ema20] > indicators[:ema200]
        end

        # Check Supertrend
        return false unless indicators[:supertrend]
        return false unless indicators[:supertrend][:direction] == :bullish

        true
      end

      def check_volume_confirmation(min_spike)
        return true if @daily_series.candles.size < 20

        volumes = @daily_series.candles.map(&:volume)
        latest_volume = volumes.last || 0
        avg_volume = volumes.sum.to_f / volumes.size

        return false if avg_volume <= 0

        (latest_volume / avg_volume) >= min_spike
      end

      def calculate_indicators
        {
          ema20: @daily_series.ema(20),
          ema50: @daily_series.ema(50),
          ema200: @daily_series.ema(200),
          supertrend: calculate_supertrend
        }
      end

      def calculate_supertrend
        st_config = AlgoConfig.fetch([:indicators, :supertrend]) || {}
        period = st_config[:period] || 10
        multiplier = st_config[:multiplier] || 3.0

        supertrend = Indicators::Supertrend.new(
          series: @daily_series,
          period: period,
          base_multiplier: multiplier
        )
        result = supertrend.call

        return nil unless result && result[:trend]

        {
          trend: result[:trend],
          value: result[:line]&.last,
          direction: result[:trend] == :bullish ? :bullish : :bearish
        }
      rescue StandardError => e
        Rails.logger.warn("[Strategies::Swing::Engine] Supertrend failed: #{e.message}")
        nil
      end

      def validate_smc_structure
        # Only validate if SMC is enabled in config
        smc_config = @config[:smc_validation] || {}
        return nil unless smc_config[:enabled]

        # Determine expected direction from indicators
        indicators = calculate_indicators
        direction = if indicators[:supertrend] && indicators[:supertrend][:direction] == :bullish
                      :long
                    elsif indicators[:supertrend] && indicators[:supertrend][:direction] == :bearish
                      :short
                    else
                      :long # Default
                    end

        Smc::StructureValidator.validate(
          @daily_series.candles,
          direction: direction,
          config: smc_config
        )
      rescue StandardError => e
        Rails.logger.warn("[Strategies::Swing::Engine] SMC validation failed: #{e.message}")
        nil
      end
    end
  end
end

