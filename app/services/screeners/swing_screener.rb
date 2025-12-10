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
      # Load from master_universe.yml if available
      universe_file = Rails.root.join('config/universe/master_universe.yml')
      if universe_file.exist?
        universe_symbols = YAML.load_file(universe_file).to_set
        Instrument.where(symbol_name: universe_symbols.to_a)
      else
        # Fallback: use all equity/index instruments
        Instrument.where(instrument_type: ['EQUITY', 'INDEX'])
      end
    end

    def passes_basic_filters?(instrument)
      # Check if instrument has candles
      return false unless instrument.has_candles?(timeframe: '1D')

      # Check price range (if LTP available)
      ltp = instrument.ltp
      if ltp
        min_price = @screening_config[:min_price] || 50
        max_price = @screening_config[:max_price] || 50_000
        return false if ltp < min_price || ltp > max_price
      end

      # Check if it's a penny stock (if enabled)
      if @screening_config[:exclude_penny_stocks] && ltp
        return false if ltp < 10
      end

      true
    end

    def analyze_instrument(instrument)
      # Load daily candles
      daily_series = instrument.load_daily_candles(limit: 100)
      return nil unless daily_series&.candles&.any?

      # Need at least 50 candles for reliable analysis
      return nil if daily_series.candles.size < 50

      # Calculate indicators
      indicators = calculate_indicators(daily_series)
      return nil unless indicators

      # Calculate score based on filters
      score = calculate_score(daily_series, indicators)

      # Build candidate hash
      {
        instrument_id: instrument.id,
        symbol: instrument.symbol_name,
        score: score,
        indicators: indicators,
        metadata: build_metadata(instrument, daily_series, indicators)
      }
    end

    def calculate_indicators(series)
      last_index = series.candles.size - 1

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
        volume: calculate_volume_metrics(series)
      }
    rescue StandardError => e
      Rails.logger.error("[Screeners::SwingScreener] Indicator calculation failed: #{e.message}")
      nil
    end

    def calculate_supertrend(series)
      st_config = @config.dig(:indicators)&.find { |i| i[:type] == 'supertrend' } || {}
      period = st_config[:period] || 10
      multiplier = st_config[:multiplier] || 3.0

      supertrend = Indicators::Supertrend.new(
        series: series,
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
        spike_ratio: avg_volume > 0 ? (latest_volume.to_f / avg_volume) : 0
      }
    end

    def calculate_score(series, indicators)
      score = 0.0
      max_score = 0.0

      # Trend alignment (EMA filters) - 30 points
      if @strategy_config.dig(:trend_filters, :use_ema20) && @strategy_config.dig(:trend_filters, :use_ema50)
        if indicators[:ema20] && indicators[:ema50]
          if indicators[:ema20] > indicators[:ema50]
            score += 15
            max_score += 15
          end
        end
      end

      if @strategy_config.dig(:trend_filters, :use_ema200)
        if indicators[:ema20] && indicators[:ema200]
          if indicators[:ema20] > indicators[:ema200]
            score += 15
            max_score += 15
          end
        end
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
      if indicators[:macd] && indicators[:macd].is_a?(Array) && indicators[:macd].size >= 2
        macd_line, signal_line = indicators[:macd][0], indicators[:macd][1]
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
      max_score > 0 ? (score / max_score * 100).round(2) : 0.0
    end

    def build_metadata(instrument, series, indicators)
      {
        ltp: instrument.ltp,
        candles_count: series.candles.size,
        latest_timestamp: series.candles.last&.timestamp,
        trend_alignment: check_trend_alignment(indicators),
        volatility: calculate_volatility(series, indicators),
        momentum: calculate_momentum(series, indicators)
      }
    end

    def check_trend_alignment(indicators)
      alignment = []

      if indicators[:ema20] && indicators[:ema50] && indicators[:ema20] > indicators[:ema50]
        alignment << :ema_bullish
      end

      if indicators[:supertrend] && indicators[:supertrend][:direction] == :bullish
        alignment << :supertrend_bullish
      end

      if indicators[:macd] && indicators[:macd].is_a?(Array) && indicators[:macd].size >= 2
        macd_line, signal_line = indicators[:macd][0], indicators[:macd][1]
        if macd_line && signal_line && macd_line > signal_line
          alignment << :macd_bullish
        end
      end

      alignment
    end

    def calculate_volatility(series, indicators)
      return nil unless indicators[:atr] && indicators[:latest_close]

      atr_pct = (indicators[:atr] / indicators[:latest_close] * 100).round(2)
      {
        atr: indicators[:atr],
        atr_percent: atr_pct,
        level: atr_pct < 2 ? :low : (atr_pct < 5 ? :medium : :high)
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
               end
      }
    end
  end
end

