# frozen_string_literal: true

module LongTerm
  class MultiTimeframeAnalyzer < ApplicationService
    TIMEFRAMES = {
      h1: "60",    # 1 hour (for entry timing)
      d1: "1D",    # Daily
      w1: "1W",    # Weekly
    }.freeze

    def self.call(instrument:, include_intraday: true, cached_candles: nil)
      new(instrument: instrument, include_intraday: include_intraday, cached_candles: cached_candles).call
    end

    def initialize(instrument:, include_intraday: true, cached_candles: nil)
      @instrument = instrument
      @include_intraday = include_intraday
      @cached_candles = cached_candles
      @config = AlgoConfig.fetch(%i[long_term_trading multi_timeframe]) || {}
    end

    def call
      return { success: false, error: "Invalid instrument" } if @instrument.blank?

      analysis = {
        instrument_id: @instrument.id,
        symbol: @instrument.symbol_name,
        timeframes: {},
        multi_timeframe_score: 0.0,
        trend_alignment: {},
        momentum_alignment: {},
        support_resistance: {},
        entry_recommendations: [],
      }

      # Load and analyze each timeframe (NO 15m for long-term)
      TIMEFRAMES.each do |tf_key, tf_value|
        next if tf_key == :h1 && !@include_intraday

        tf_analysis = analyze_timeframe(tf_key, tf_value)
        analysis[:timeframes][tf_key] = tf_analysis if tf_analysis
      end

      # Calculate multi-timeframe metrics
      analysis[:multi_timeframe_score] = calculate_mtf_score(analysis[:timeframes])
      analysis[:trend_alignment] = analyze_trend_alignment(analysis[:timeframes])
      analysis[:momentum_alignment] = analyze_momentum_alignment(analysis[:timeframes])
      analysis[:support_resistance] = identify_support_resistance(analysis[:timeframes])
      analysis[:entry_recommendations] = generate_entry_recommendations(analysis)

      {
        success: true,
        analysis: analysis,
      }
    rescue StandardError => e
      log_error("Long-term multi-timeframe analysis failed: #{e.message}")
      { success: false, error: e.message }
    end

    private

    def analyze_timeframe(tf_key, tf_value)
      # Load candles for this timeframe
      series = load_timeframe_candles(tf_value)
      return nil unless series&.candles&.any?

      # Need minimum candles for reliable analysis
      min_candles = case tf_key
                    when :h1 then 30
                    when :d1 then 50
                    when :w1 then 20
                    else 30
                    end

      return nil if series.candles.size < min_candles

      # Calculate indicators
      indicators = calculate_indicators(series, tf_key)

      # Calculate trend score
      trend_score = calculate_trend_score(indicators, series)

      # Calculate momentum score
      momentum_score = calculate_momentum_score(indicators, series)

      # Identify structure
      structure = identify_structure(series, indicators)

      {
        timeframe: tf_value,
        candles_count: series.candles.size,
        latest_close: series.latest_close,
        latest_timestamp: series.latest_candle&.timestamp,
        indicators: indicators,
        trend_score: trend_score,
        momentum_score: momentum_score,
        structure: structure,
        trend_direction: determine_trend_direction(indicators),
        momentum_direction: determine_momentum_direction(indicators, series),
      }
    end

    def load_timeframe_candles(tf_value)
      # Check cache first to avoid N+1 queries
      if @cached_candles && @cached_candles[@instrument.id] && @cached_candles[@instrument.id][tf_value]
        return @cached_candles[@instrument.id][tf_value]
      end

      case tf_value
      when "60"
        # Load 1h candles (on-demand)
        result = Candles::IntradayFetcher.call(
          instrument: @instrument,
          interval: "60",
          days: 10, # More days for long-term analysis
        )
        return nil unless result[:success]

        # Convert to CandleSeries
        series = CandleSeries.new(symbol: @instrument.symbol_name, interval: tf_value)
        result[:candles].each do |candle_data|
          series.add_candle(
            Candle.new(
              timestamp: candle_data[:timestamp] || Time.zone.parse(candle_data["timestamp"].to_s),
              open: candle_data[:open] || candle_data["open"],
              high: candle_data[:high] || candle_data["high"],
              low: candle_data[:low] || candle_data["low"],
              close: candle_data[:close] || candle_data["close"],
              volume: candle_data[:volume] || candle_data["volume"] || 0,
            ),
          )
        end
        series
      when "1D"
        @instrument.load_daily_candles(limit: 200)
      when "1W"
        @instrument.load_weekly_candles(limit: 52)
      else
        nil
      end
    end

    def calculate_indicators(series, tf_key)
      {
        ema20: series.ema(20),
        ema50: series.ema(50),
        ema200: series.ema(200),
        rsi: series.rsi(14),
        adx: series.adx(14),
        atr: series.atr(14),
        macd: series.macd(12, 26, 9),
        supertrend: calculate_supertrend(series),
        volume: calculate_volume_metrics(series),
        bollinger_bands: series.bollinger_bands(period: 20),
      }
    rescue StandardError => e
      log_warn("Indicator calculation failed for #{tf_key}: #{e.message}")
      {}
    end

    def calculate_supertrend(series)
      st_config = AlgoConfig.fetch(%i[indicators supertrend]) || {}
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
      log_warn("Supertrend calculation failed: #{e.message}")
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

    def calculate_trend_score(indicators, series)
      score = 0.0
      max_score = 0.0

      # EMA alignment (40 points)
      if indicators[:ema20] && indicators[:ema50]
        if indicators[:ema20] > indicators[:ema50]
          score += 20
        end
        max_score += 20
      end

      if indicators[:ema20] && indicators[:ema200]
        if indicators[:ema20] > indicators[:ema200]
          score += 20
        end
        max_score += 20
      end

      # Supertrend (30 points)
      if indicators[:supertrend] && indicators[:supertrend][:direction] == :bullish
        score += 30
      end
      max_score += 30

      # ADX strength (30 points)
      if indicators[:adx]
        if indicators[:adx] > 25
          score += 30
        elsif indicators[:adx] > 20
          score += 15
        end
        max_score += 30
      end

      max_score.positive? ? (score / max_score * 100).round(2) : 0.0
    end

    def calculate_momentum_score(indicators, series)
      score = 0.0
      max_score = 0.0

      # RSI momentum (30 points)
      if indicators[:rsi]
        if indicators[:rsi] > 50 && indicators[:rsi] < 70
          score += 30
        elsif indicators[:rsi] > 40 && indicators[:rsi] < 60
          score += 15
        end
        max_score += 30
      end

      # MACD momentum (30 points)
      if indicators[:macd].is_a?(Array) && indicators[:macd].size >= 2
        macd_line = indicators[:macd][0]
        signal_line = indicators[:macd][1]
        if macd_line && signal_line && macd_line > signal_line
          score += 30
        end
        max_score += 30
      end

      # Price momentum (40 points) - longer period for long-term
      closes = series.closes
      if closes.size >= 10 # Use 10-period for long-term
        change_10 = ((closes.last - closes[-10]) / closes[-10] * 100).round(2)
        if change_10.positive?
          score += [40, (change_10 * 2)].min
        end
      end
      max_score += 40

      max_score.positive? ? (score / max_score * 100).round(2) : 0.0
    end

    def identify_structure(series, indicators)
      return {} if series.candles.size < 20

      {
        swing_highs: identify_swing_highs(series),
        swing_lows: identify_swing_lows(series),
        higher_highs: check_higher_highs(series),
        higher_lows: check_higher_lows(series),
        trend_strength: calculate_trend_strength(series, indicators),
      }
    end

    def identify_swing_highs(series)
      return [] if series.candles.size < 5

      highs = []
      candles = series.candles

      (2..(candles.size - 3)).each do |i|
        if candles[i].high > candles[i - 1].high &&
           candles[i].high > candles[i - 2].high &&
           candles[i].high > candles[i + 1].high &&
           candles[i].high > candles[i + 2].high
          highs << { index: i, price: candles[i].high, timestamp: candles[i].timestamp }
        end
      end

      highs.last(5)
    end

    def identify_swing_lows(series)
      return [] if series.candles.size < 5

      lows = []
      candles = series.candles

      (2..(candles.size - 3)).each do |i|
        if candles[i].low < candles[i - 1].low &&
           candles[i].low < candles[i - 2].low &&
           candles[i].low < candles[i + 1].low &&
           candles[i].low < candles[i + 2].low
          lows << { index: i, price: candles[i].low, timestamp: candles[i].timestamp }
        end
      end

      lows.last(5)
    end

    def check_higher_highs(series)
      swing_highs = identify_swing_highs(series)
      return false if swing_highs.size < 2

      swing_highs.last(2).map { |sh| sh[:price] }.reduce(:>) || false
    end

    def check_higher_lows(series)
      swing_lows = identify_swing_lows(series)
      return false if swing_lows.size < 2

      swing_lows.last(2).map { |sl| sl[:price] }.reduce(:>) || false
    end

    def calculate_trend_strength(series, indicators)
      return 0.0 if series.candles.size < 20

      closes = series.closes
      return 0.0 if closes.empty?

      # Calculate linear regression slope (longer period for long-term)
      n = [closes.size, 30].min # Use 30 periods for long-term
      x_values = (0...n).to_a
      y_values = closes.last(n)

      x_mean = x_values.sum.to_f / n
      y_mean = y_values.sum.to_f / n

      numerator = x_values.zip(y_values).sum { |x, y| (x - x_mean) * (y - y_mean) }
      denominator = x_values.sum { |x| (x - x_mean)**2 }

      return 0.0 if denominator.zero?

      slope = numerator / denominator
      (slope / y_mean * 100).round(2)
    end

    def determine_trend_direction(indicators)
      return :neutral unless indicators[:supertrend]

      indicators[:supertrend][:direction] == :bullish ? :bullish : :bearish
    end

    def determine_momentum_direction(indicators, series)
      closes = series.closes
      return :neutral if closes.size < 10

      # Use 10-period change for long-term
      change = ((closes.last - closes[-10]) / closes[-10] * 100).round(2)

      if change > 2
        :bullish
      elsif change < -2
        :bearish
      else
        :neutral
      end
    end

    def calculate_mtf_score(timeframes)
      return 0.0 if timeframes.empty?

      # Long-Term Trading Weights: More weight to weekly and daily
      weights = {
        w1: 0.4,  # Weekly: 40% (primary for long-term)
        d1: 0.35, # Daily: 35%
        h1: 0.25, # Hourly: 25% (for entry timing only)
      }

      total_score = 0.0
      total_weight = 0.0

      timeframes.each do |tf_key, tf_data|
        weight = weights[tf_key.to_sym] || 0.0
        next if weight.zero?

        trend_score = tf_data[:trend_score] || 0
        momentum_score = tf_data[:momentum_score] || 0
        combined_score = (trend_score * 0.6 + momentum_score * 0.4)

        total_score += combined_score * weight
        total_weight += weight
      end

      total_weight.positive? ? (total_score / total_weight).round(2) : 0.0
    end

    def analyze_trend_alignment(timeframes)
      alignment = {
        bullish_count: 0,
        bearish_count: 0,
        neutral_count: 0,
        aligned: false,
      }

      directions = timeframes.values.map { |tf| tf[:trend_direction] }.compact

      return alignment if directions.empty?

      alignment[:bullish_count] = directions.count(:bullish)
      alignment[:bearish_count] = directions.count(:bearish)
      alignment[:neutral_count] = directions.count(:neutral)

      # For long-term, require stronger alignment (at least 2/3 bullish)
      alignment[:aligned] = alignment[:bullish_count] > alignment[:bearish_count] &&
                            alignment[:bullish_count] >= (directions.size * 0.67).ceil

      alignment
    end

    def analyze_momentum_alignment(timeframes)
      alignment = {
        bullish_count: 0,
        bearish_count: 0,
        neutral_count: 0,
        aligned: false,
      }

      directions = timeframes.values.map { |tf| tf[:momentum_direction] }.compact

      return alignment if directions.empty?

      alignment[:bullish_count] = directions.count(:bullish)
      alignment[:bearish_count] = directions.count(:bearish)
      alignment[:neutral_count] = directions.count(:neutral)

      alignment[:aligned] = alignment[:bullish_count] > alignment[:bearish_count]

      alignment
    end

    def identify_support_resistance(timeframes)
      # Use weekly and daily for major S/R levels
      # Use 1h for entry timing only
      daily_tf = timeframes[:d1]
      weekly_tf = timeframes[:w1]
      h1_tf = timeframes[:h1]

      support_levels = []
      resistance_levels = []

      # Major support/resistance from weekly and daily
      if daily_tf && daily_tf[:structure][:swing_lows]
        support_levels += daily_tf[:structure][:swing_lows].map { |sl| sl[:price] }
      end

      if weekly_tf && weekly_tf[:structure][:swing_lows]
        support_levels += weekly_tf[:structure][:swing_lows].map { |sl| sl[:price] }
      end

      if daily_tf && daily_tf[:structure][:swing_highs]
        resistance_levels += daily_tf[:structure][:swing_highs].map { |sh| sh[:price] }
      end

      if weekly_tf && weekly_tf[:structure][:swing_highs]
        resistance_levels += weekly_tf[:structure][:swing_highs].map { |sh| sh[:price] }
      end

      # 1h support/resistance for entry timing only
      if h1_tf && h1_tf[:structure]
        if h1_tf[:structure][:swing_lows]&.any?
          h1_supports = h1_tf[:structure][:swing_lows].map { |sl| sl[:price] }
          support_levels += h1_supports.last(2) # Last 2 swing lows from 1h
        end

        if h1_tf[:structure][:swing_highs]&.any?
          h1_resistances = h1_tf[:structure][:swing_highs].map { |sh| sh[:price] }
          resistance_levels += h1_resistances.last(2) # Last 2 swing highs from 1h
        end
      end

      {
        support_levels: support_levels.uniq.sort.reverse.first(5),
        resistance_levels: resistance_levels.uniq.sort.first(5),
        intraday_support: h1_tf&.dig(:structure, :swing_lows)&.last(2)&.map { |sl| sl[:price] } || [],
        intraday_resistance: h1_tf&.dig(:structure, :swing_highs)&.last(2)&.map { |sh| sh[:price] } || [],
      }
    end

    def generate_entry_recommendations(analysis)
      recommendations = []

      # Only recommend if trend is aligned (stronger requirement for long-term)
      return recommendations unless analysis[:trend_alignment][:aligned]

      daily_tf = analysis[:timeframes][:d1]
      weekly_tf = analysis[:timeframes][:w1]
      return recommendations unless daily_tf && weekly_tf

      current_price = daily_tf[:latest_close]
      support_levels = analysis[:support_resistance][:support_levels]

      # Get 1h for entry timing
      h1_tf = analysis[:timeframes][:h1]
      h1_bullish = h1_tf && h1_tf[:trend_direction] == :bullish && h1_tf[:momentum_direction] == :bullish

      # Long-term entries: Focus on weekly/daily support with 1h confirmation
      if support_levels.any? && current_price > support_levels.first
        nearest_support = support_levels.first
        distance_pct = ((current_price - nearest_support) / nearest_support * 100).round(2)

        if distance_pct < 5 # Within 5% of support (wider for long-term)
          entry_confidence = calculate_entry_confidence(analysis, :support_bounce)
          entry_confidence += 5 if h1_bullish # 1h confirms

          recommendations << {
            type: :long_term_support,
            entry_zone: [nearest_support, current_price],
            stop_loss: nearest_support * 0.95, # 5% below support (wider for long-term)
            confidence: [[entry_confidence, 100].min, 0].max.round(2),
            intraday_confirmation: {
              h1_bullish: h1_bullish,
            },
          }
        end
      end

      # Long-term breakout entries
      resistance_levels = analysis[:support_resistance][:resistance_levels]
      if resistance_levels.any?
        nearest_resistance = resistance_levels.first
        distance_pct = ((nearest_resistance - current_price) / current_price * 100).round(2)

        if distance_pct < 3 # Within 3% of resistance
          entry_confidence = calculate_entry_confidence(analysis, :breakout)
          entry_confidence += 5 if h1_bullish

          recommendations << {
            type: :long_term_breakout,
            entry_zone: [current_price, nearest_resistance * 1.02],
            stop_loss: current_price * 0.93, # 7% below entry (wider for long-term)
            confidence: [[entry_confidence, 100].min, 0].max.round(2),
            intraday_confirmation: {
              h1_bullish: h1_bullish,
            },
          }
        end
      end

      recommendations.sort_by { |r| -r[:confidence] }
    end

    def calculate_entry_confidence(analysis, entry_type)
      base_confidence = analysis[:multi_timeframe_score]

      # Boost confidence if momentum is aligned
      if analysis[:momentum_alignment][:aligned]
        base_confidence += 10
      end

      # Boost confidence based on timeframe alignment
      bullish_tfs = analysis[:trend_alignment][:bullish_count]
      total_tfs = analysis[:timeframes].size
      alignment_pct = (bullish_tfs.to_f / total_tfs * 100).round(2)
      base_confidence += (alignment_pct / 10).round(2)

      [[base_confidence, 100].min, 0].max.round(2)
    end
  end
end
