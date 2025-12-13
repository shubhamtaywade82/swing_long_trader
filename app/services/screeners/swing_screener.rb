# frozen_string_literal: true

module Screeners
  class SwingScreener < ApplicationService
    DEFAULT_LIMIT = 50

    def self.call(instruments: nil, limit: nil)
      new(instruments: instruments, limit: limit).call
    end

    def initialize(instruments: nil, limit: nil)
      @instruments = instruments || load_universe
      @limit = limit || DEFAULT_LIMIT
      @config = AlgoConfig.fetch[:swing_trading] || {}
      @screening_config = @config[:screening] || {}
      @strategy_config = @config[:strategy] || {}
    end

    def call
      candidates = []

      @instruments.find_each(batch_size: 50) do |instrument|
        next unless passes_basic_filters?(instrument)

        analysis = analyze_instrument(instrument)
        next unless analysis

        candidates << analysis
      end

      # Sort by score (descending) and return top N
      candidates.sort_by { |c| -c[:score] }.first(@limit)
    end

    private

    def load_universe
      # Load from IndexConstituent database table (preferred)
      if IndexConstituent.exists?
        universe_symbols = IndexConstituent.distinct.pluck(:symbol).map(&:upcase)
        Instrument.where(symbol_name: universe_symbols)
                 .or(Instrument.where(isin: IndexConstituent.where.not(isin_code: nil).distinct.pluck(:isin_code).map(&:upcase)))
      else
        # Fallback: use all equity/index instruments from NSE
        Instrument.where(segment: %w[equity index], exchange: "NSE")
      end
    end

    def passes_basic_filters?(instrument)
      # Check if instrument has candles
      return false unless instrument.has_candles?(timeframe: "1D")

      # Check price range (if LTP available)
      ltp = instrument.ltp
      if ltp
        min_price = @screening_config[:min_price] || 50
        max_price = @screening_config[:max_price] || 50_000
        return false if ltp < min_price || ltp > max_price
      end

      # Check if it's a penny stock (if enabled)
      return false if @screening_config[:exclude_penny_stocks] && ltp && (ltp < 10)

      true
    end

    def analyze_instrument(instrument)
      # Multi-timeframe analysis
      mtf_result = Swing::MultiTimeframeAnalyzer.call(
        instrument: instrument,
        include_intraday: @config.dig(:multi_timeframe, :include_intraday) != false,
      )

      return nil unless mtf_result[:success]

      mtf_analysis = mtf_result[:analysis]

      # Load daily candles for backward compatibility
      daily_series = instrument.load_daily_candles(limit: 100)
      return nil unless daily_series&.candles&.any?

      # Need at least 50 candles for reliable analysis
      return nil if daily_series.candles.size < 50

      # Calculate indicators (from daily for backward compatibility)
      indicators = calculate_indicators(daily_series)
      return nil unless indicators

      # Calculate score based on filters (enhanced with MTF)
      base_score = calculate_score(daily_series, indicators)
      mtf_score = mtf_analysis[:multi_timeframe_score] || 0

      # Combined score: 60% base score, 40% MTF score
      combined_score = (base_score * 0.6 + mtf_score * 0.4).round(2)

      # Validate SMC structure (optional)
      smc_validation = validate_smc_structure(daily_series, indicators)

      # Build candidate hash with multi-timeframe data
      {
        instrument_id: instrument.id,
        symbol: instrument.symbol_name,
        score: combined_score,
        base_score: base_score,
        mtf_score: mtf_score,
        indicators: indicators,
        multi_timeframe: mtf_analysis,
        metadata: build_metadata(instrument, daily_series, indicators, smc_validation, mtf_analysis),
      }
    end

    def calculate_indicators(series)
      _last_index = series.candles.size - 1

      {
        ema20: series.ema(20),
        ema50: series.ema(50),
        ema200: series.ema(200),
        rsi: series.rsi(14),
        adx: series.adx(14),
        atr: series.atr(14),
        macd: series.macd(12, 26, 9),
        supertrend: calculate_supertrend(series),
        latest_close: series.candles.last&.close,
        volume: calculate_volume_metrics(series),
      }
    rescue StandardError => e
      Rails.logger.error("[Screeners::SwingScreener] Indicator calculation failed: #{e.message}")
      nil
    end

    def calculate_supertrend(series)
      st_config = @config[:indicators]&.find { |i| i[:type] == "supertrend" } || {}
      period = st_config[:period] || 10
      multiplier = st_config[:multiplier] || 3.0

      supertrend = Indicators::Supertrend.new(
        series: series,
        period: period,
        base_multiplier: multiplier,
      )
      result = supertrend.call

      return nil unless result && result[:trend]

      {
        trend: result[:trend],
        value: result[:line]&.last,
        direction: result[:trend] == :bullish ? :bullish : :bearish,
      }
    rescue StandardError => e
      Rails.logger.warn("[Screeners::SwingScreener] Supertrend calculation failed: #{e.message}")
      nil
    end

    def calculate_volume_metrics(series)
      return {} if series.candles.empty?

      volumes = series.candles.map(&:volume)
      latest_volume = volumes.last || 0
      avg_volume = volumes.sum.to_f / volumes.size

      {
        latest: latest_volume,
        average: avg_volume,
        spike_ratio: avg_volume.positive? ? (latest_volume.to_f / avg_volume) : 0,
      }
    end

    def calculate_score(_series, indicators)
      score = 0.0
      max_score = 0.0

      # Trend alignment (EMA filters) - 30 points
      if @strategy_config.dig(:trend_filters,
                              :use_ema20) && @strategy_config.dig(:trend_filters,
                                                                  :use_ema50) && indicators[:ema20] && indicators[:ema50] && (indicators[:ema20] > indicators[:ema50])
        score += 15
        max_score += 15
      end

      if @strategy_config.dig(:trend_filters,
                              :use_ema200) && indicators[:ema20] && indicators[:ema200] && (indicators[:ema20] > indicators[:ema200])
        score += 15
        max_score += 15
      end

      # Supertrend alignment - 20 points
      if indicators[:supertrend] && indicators[:supertrend][:direction] == :bullish
        score += 20
        max_score += 20
      end

      # ADX strength - 15 points
      if indicators[:adx]
        if indicators[:adx] > 25
          score += 15
        elsif indicators[:adx] > 20
          score += 10
        end
        max_score += 15
      end

      # RSI condition - 10 points
      if indicators[:rsi]
        if indicators[:rsi] > 50 && indicators[:rsi] < 70
          score += 10
        elsif indicators[:rsi] > 40 && indicators[:rsi] < 60
          score += 5
        end
        max_score += 10
      end

      # MACD bullish - 10 points
      if indicators[:macd].is_a?(Array) && indicators[:macd].size >= 2
        macd_line = indicators[:macd][0]
        signal_line = indicators[:macd][1]
        if macd_line && signal_line && macd_line > signal_line
          score += 10
          max_score += 10
        end
      end

      # Volume confirmation - 15 points
      if @strategy_config.dig(:entry_conditions, :require_volume_confirmation)
        min_spike = @strategy_config.dig(:entry_conditions, :min_volume_spike) || 1.5
        if indicators[:volume][:spike_ratio] >= min_spike
          score += 15
          max_score += 15
        end
      end

      # Normalize to 0-100 scale
      max_score.positive? ? (score / max_score * 100).round(2) : 0.0
    end

    def build_metadata(instrument, series, indicators, smc_validation = nil, mtf_analysis = nil)
      metadata = {
        ltp: instrument.ltp,
        candles_count: series.candles.size,
        latest_timestamp: series.candles.last&.timestamp,
        trend_alignment: check_trend_alignment(indicators),
        volatility: calculate_volatility(series, indicators),
        momentum: calculate_momentum(series, indicators),
      }

      # Add multi-timeframe metadata
      if mtf_analysis
        metadata[:multi_timeframe] = {
          score: mtf_analysis[:multi_timeframe_score],
          trend_alignment: mtf_analysis[:trend_alignment],
          momentum_alignment: mtf_analysis[:momentum_alignment],
          timeframes_analyzed: mtf_analysis[:timeframes].keys,
          entry_recommendations: mtf_analysis[:entry_recommendations],
        }
      end

      # Add SMC validation if available
      if smc_validation
        metadata[:smc_validation] = {
          valid: smc_validation[:valid],
          score: smc_validation[:score],
          reasons: smc_validation[:reasons],
        }
      end

      metadata
    end

    def validate_smc_structure(series, indicators)
      # Only validate if SMC is enabled in config
      smc_config = @strategy_config[:smc_validation] || {}
      return nil unless smc_config[:enabled]

      # Determine expected direction from indicators
      direction = if indicators[:supertrend] && indicators[:supertrend][:direction] == :bullish
                    :long
                  elsif indicators[:supertrend] && indicators[:supertrend][:direction] == :bearish
                    :short
                  else
                    :long # Default
                  end

      Smc::StructureValidator.validate(
        series.candles,
        direction: direction,
        config: smc_config,
      )
    rescue StandardError => e
      Rails.logger.warn("[Screeners::SwingScreener] SMC validation failed: #{e.message}")
      nil
    end

    def check_trend_alignment(indicators)
      alignment = []

      alignment << :ema_bullish if indicators[:ema20] && indicators[:ema50] && indicators[:ema20] > indicators[:ema50]

      alignment << :supertrend_bullish if indicators[:supertrend] && indicators[:supertrend][:direction] == :bullish

      if indicators[:macd].is_a?(Array) && indicators[:macd].size >= 2
        macd_line = indicators[:macd][0]
        signal_line = indicators[:macd][1]
        alignment << :macd_bullish if macd_line && signal_line && macd_line > signal_line
      end

      alignment
    end

    def calculate_volatility(_series, indicators)
      return nil unless indicators[:atr] && indicators[:latest_close]

      atr_pct = (indicators[:atr] / indicators[:latest_close] * 100).round(2)
      {
        atr: indicators[:atr],
        atr_percent: atr_pct,
        level: if atr_pct < 2
                 :low
               else
                 (atr_pct < 5 ? :medium : :high)
               end,
      }
    end

    def calculate_momentum(series, indicators)
      return nil unless series.candles.size >= 5

      closes = series.closes
      recent_change = ((closes.last - closes[-5]) / closes[-5] * 100).round(2)

      {
        change_5d: recent_change,
        rsi: indicators[:rsi],
        level: case indicators[:rsi]
               when 0..30
                 :oversold
               when 70..100
                 :overbought
               else
                 :neutral
               end,
      }
    end
  end
end
