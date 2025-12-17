# frozen_string_literal: true

module Swing
  class MultiTimeframeAnalyzer < ApplicationService
    TIMEFRAMES = {
      m15: "15",   # 15 minutes
      h1: "60",    # 1 hour
      d1: "1D",    # Daily
      w1: "1W",    # Weekly
    }.freeze

    def self.call(instrument:, include_intraday: true, cached_candles: nil)
      new(instrument: instrument, include_intraday: include_intraday, cached_candles: cached_candles).call
    end

    def initialize(instrument:, include_intraday: true, trading_style: :swing, cached_candles: nil)
      @instrument = instrument
      @include_intraday = include_intraday
      @trading_style = trading_style
      @cached_candles = cached_candles
      @config = AlgoConfig.fetch(%i[swing_trading multi_timeframe]) || {}
    end

    def call
      return { success: false, error: "Invalid instrument" } if @instrument.blank?

      # Ensure candles are fresh before analysis (only check, don't auto-ingest in analysis)
      # Auto-ingestion should happen at screener level, not during individual analysis
      unless Rails.env.test?
        daily_freshness = Candles::FreshnessChecker.check_freshness(timeframe: "1D")
        weekly_freshness = Candles::FreshnessChecker.check_freshness(timeframe: "1W")
        if !daily_freshness[:fresh] || !weekly_freshness[:fresh]
          Rails.logger.warn(
            "[Swing::MultiTimeframeAnalyzer] Analyzing with stale candles: " \
            "Daily: #{daily_freshness[:freshness_percentage]&.round(1)}% fresh, " \
            "Weekly: #{weekly_freshness[:freshness_percentage]&.round(1)}% fresh",
          )
        end
      end

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

      # Load and analyze each timeframe
      TIMEFRAMES.each do |tf_key, tf_value|
        next if tf_key == :m15 && !@include_intraday
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
      log_error("Multi-timeframe analysis failed: #{e.message}")
      { success: false, error: e.message }
    end

    private

    def analyze_timeframe(tf_key, tf_value)
      # Load candles for this timeframe
      series = load_timeframe_candles(tf_value)
      return nil unless series&.candles&.any?

      # Need minimum candles for reliable analysis
      min_candles = case tf_key
                    when :m15 then 50
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
      when "15", "60"
        # Load intraday candles (on-demand, not stored)
        result = Candles::IntradayFetcher.call(
          instrument: @instrument,
          interval: tf_value,
          days: tf_value == "15" ? 2 : 5, # 15m: 2 days, 1h: 5 days
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
        score += 20 if indicators[:ema20] > indicators[:ema50]
        max_score += 20
      end

      if indicators[:ema20] && indicators[:ema200]
        score += 20 if indicators[:ema20] > indicators[:ema200]
        max_score += 20
      end

      # Supertrend (30 points)
      score += 30 if indicators[:supertrend] && indicators[:supertrend][:direction] == :bullish
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
        score += 30 if macd_line && signal_line && macd_line > signal_line
        max_score += 30
      end

      # Price momentum (40 points)
      closes = series.closes
      if closes.size >= 5
        change_5 = ((closes.last - closes[-5]) / closes[-5] * 100).round(2)
        if change_5.positive?
          score += [40, (change_5 * 2)].min # Cap at 40
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
        next unless candles[i].high > candles[i - 1].high &&
                    candles[i].high > candles[i - 2].high &&
                    candles[i].high > candles[i + 1].high &&
                    candles[i].high > candles[i + 2].high

        highs << { index: i, price: candles[i].high, timestamp: candles[i].timestamp }
      end

      highs.last(5) # Return last 5 swing highs
    end

    def identify_swing_lows(series)
      return [] if series.candles.size < 5

      lows = []
      candles = series.candles

      (2..(candles.size - 3)).each do |i|
        next unless candles[i].low < candles[i - 1].low &&
                    candles[i].low < candles[i - 2].low &&
                    candles[i].low < candles[i + 1].low &&
                    candles[i].low < candles[i + 2].low

        lows << { index: i, price: candles[i].low, timestamp: candles[i].timestamp }
      end

      lows.last(5) # Return last 5 swing lows
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

      # Calculate linear regression slope
      n = [closes.size, 20].min
      x_values = (0...n).to_a
      y_values = closes.last(n)

      x_mean = x_values.sum.to_f / n
      y_mean = y_values.sum.to_f / n

      numerator = x_values.zip(y_values).sum { |x, y| (x - x_mean) * (y - y_mean) }
      denominator = x_values.sum { |x| (x - x_mean)**2 }

      return 0.0 if denominator.zero?

      slope = numerator / denominator
      (slope / y_mean * 100).round(2) # Normalize as percentage
    end

    def determine_trend_direction(indicators)
      return :neutral unless indicators[:supertrend]

      indicators[:supertrend][:direction] == :bullish ? :bullish : :bearish
    end

    def determine_momentum_direction(indicators, series)
      closes = series.closes
      return :neutral if closes.size < 5

      change = ((closes.last - closes[-5]) / closes[-5] * 100).round(2)

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

      # Weight timeframes by trading style
      # Swing Trading: More weight to daily and intraday (1d, 1h, 15m)
      # Long-Term Trading: More weight to weekly and daily (1w, 1d, 1h)
      trading_style = @trading_style || @config[:trading_style] || :swing

      weights = if %i[long_term longterm].include?(trading_style)
                  {
                    w1: 0.4,  # Weekly: 40% (primary for long-term)
                    d1: 0.35, # Daily: 35%
                    h1: 0.25, # Hourly: 25% (for entry timing)
                    m15: 0.0, # 15min: 0% (not used for long-term)
                  }
                else
                  # Swing Trading (default) - More weight to 1d, 1h, 15m
                  {
                    w1: 0.2,  # Weekly: 20% (trend context only)
                    d1: 0.4,  # Daily: 40% (primary timeframe)
                    h1: 0.25, # Hourly: 25% (entry timing)
                    m15: 0.15, # 15min: 15% (precise entry)
                  }
                end

      total_score = 0.0
      total_weight = 0.0

      timeframes.each do |tf_key, tf_data|
        weight = weights[tf_key.to_sym] || 0.0
        next if weight.zero? # Skip timeframes with 0 weight

        trend_score = tf_data[:trend_score] || 0
        momentum_score = tf_data[:momentum_score] || 0
        combined_score = ((trend_score * 0.6) + (momentum_score * 0.4))

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

      # Consider aligned if majority are bullish
      alignment[:aligned] = alignment[:bullish_count] > alignment[:bearish_count] &&
                            alignment[:bullish_count] >= (directions.size / 2.0).ceil

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
      # Use daily and weekly for major S/R levels
      # Use 1h for intraday S/R levels (for entry timing)
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

      # Intraday support/resistance from 1h (for entry timing)
      if h1_tf && h1_tf[:structure]
        if h1_tf[:structure][:swing_lows]&.any?
          # Add 1h support levels (for intraday entry timing)
          h1_supports = h1_tf[:structure][:swing_lows].map { |sl| sl[:price] }
          support_levels += h1_supports.last(3) # Last 3 swing lows from 1h
        end

        if h1_tf[:structure][:swing_highs]&.any?
          # Add 1h resistance levels
          h1_resistances = h1_tf[:structure][:swing_highs].map { |sh| sh[:price] }
          resistance_levels += h1_resistances.last(3) # Last 3 swing highs from 1h
        end
      end

      {
        support_levels: support_levels.uniq.sort.last(5).reverse, # Top 5 support levels
        resistance_levels: resistance_levels.uniq.sort.first(5), # Top 5 resistance levels
        intraday_support: h1_tf&.dig(:structure, :swing_lows)&.last(2)&.map { |sl| sl[:price] } || [],
        intraday_resistance: h1_tf&.dig(:structure, :swing_highs)&.last(2)&.map { |sh| sh[:price] } || [],
      }
    end

    def generate_entry_recommendations(analysis)
      recommendations = []

      # Only recommend if trend is aligned
      return recommendations unless analysis[:trend_alignment][:aligned]

      daily_tf = analysis[:timeframes][:d1]
      return recommendations unless daily_tf

      current_price = daily_tf[:latest_close]
      support_levels = analysis[:support_resistance][:support_levels]

      # Get intraday timeframes for entry timing
      h1_tf = analysis[:timeframes][:h1]
      m15_tf = analysis[:timeframes][:m15]

      # Use 1h for entry timing confirmation
      h1_bullish = h1_tf && h1_tf[:trend_direction] == :bullish && h1_tf[:momentum_direction] == :bullish
      # Use 15m for precise entry timing
      m15_bullish = m15_tf && m15_tf[:trend_direction] == :bullish && m15_tf[:momentum_direction] == :bullish

      # Recommend entry near support if price is above support
      if support_levels.any? && current_price > support_levels.first
        nearest_support = support_levels.first
        distance_pct = ((current_price - nearest_support) / nearest_support * 100).round(2)

        if distance_pct < 3 # Within 3% of support
          # Enhance confidence if intraday timeframes confirm
          entry_confidence = calculate_entry_confidence(analysis, :support_bounce)
          entry_confidence += 5 if h1_bullish # 1h confirms
          entry_confidence += 5 if m15_bullish # 15m confirms

          # Use 15m/1h for precise entry zone if available
          entry_zone_low = nearest_support
          entry_zone_high = current_price

          if m15_tf && m15_tf[:latest_close]
            # Use 15m close as upper bound for entry zone
            entry_zone_high = [current_price, m15_tf[:latest_close]].max
          end

          recommendations << {
            type: :support_bounce,
            entry_zone: [entry_zone_low, entry_zone_high],
            stop_loss: nearest_support * 0.98, # 2% below support
            confidence: [[entry_confidence, 100].min, 0].max.round(2),
            intraday_confirmation: {
              h1_bullish: h1_bullish,
              m15_bullish: m15_bullish,
            },
          }
        end
      end

      # Recommend breakout entry if price is near resistance
      resistance_levels = analysis[:support_resistance][:resistance_levels]
      if resistance_levels.any?
        nearest_resistance = resistance_levels.first
        distance_pct = ((nearest_resistance - current_price) / current_price * 100).round(2)

        if distance_pct < 2 # Within 2% of resistance
          # Enhance confidence if intraday timeframes confirm breakout
          entry_confidence = calculate_entry_confidence(analysis, :breakout)
          entry_confidence += 5 if h1_bullish # 1h confirms
          entry_confidence += 5 if m15_bullish # 15m confirms

          # Use 15m/1h for precise entry zone
          entry_zone_low = current_price
          entry_zone_high = nearest_resistance * 1.01

          if m15_tf && m15_tf[:latest_close] && m15_tf[:latest_close] > current_price
            # Use 15m close if it's above current price (breakout confirmation)
            entry_zone_low = [current_price, m15_tf[:latest_close]].min
          end

          recommendations << {
            type: :breakout,
            entry_zone: [entry_zone_low, entry_zone_high],
            stop_loss: current_price * 0.97, # 3% below entry
            confidence: [[entry_confidence, 100].min, 0].max.round(2),
            intraday_confirmation: {
              h1_bullish: h1_bullish,
              m15_bullish: m15_bullish,
            },
          }
        end
      end

      # Add intraday pullback entry if 15m/1h show pullback but daily/weekly are bullish
      if h1_tf && m15_tf && daily_tf[:trend_direction] == :bullish
        # Check if 15m/1h show pullback (momentum neutral/bearish but trend still bullish)
        h1_pullback = h1_tf[:trend_direction] == :bullish && h1_tf[:momentum_direction] == :neutral
        m15_pullback = m15_tf[:trend_direction] == :bullish && m15_tf[:momentum_direction] == :neutral

        if h1_pullback || m15_pullback
          # Find support from 1h timeframe
          h1_support = h1_tf[:structure][:swing_lows]&.last&.dig(:price) if h1_tf[:structure]
          h1_support ||= m15_tf[:structure][:swing_lows]&.last&.dig(:price) if m15_tf[:structure]

          if h1_support && current_price > h1_support && current_price < h1_support * 1.02
            recommendations << {
              type: :intraday_pullback,
              entry_zone: [h1_support, current_price],
              stop_loss: h1_support * 0.99, # 1% below 1h support
              confidence: calculate_entry_confidence(analysis, :intraday_pullback),
              intraday_confirmation: {
                h1_pullback: h1_pullback,
                m15_pullback: m15_pullback,
                timeframe: h1_pullback ? "1h" : "15m",
              },
            }
          end
        end
      end

      recommendations.sort_by { |r| -r[:confidence] }
    end

    def calculate_entry_confidence(analysis, entry_type)
      base_confidence = analysis[:multi_timeframe_score]

      # Boost confidence if momentum is aligned
      base_confidence += 10 if analysis[:momentum_alignment][:aligned]

      # Boost confidence based on timeframe alignment
      bullish_tfs = analysis[:trend_alignment][:bullish_count]
      total_tfs = analysis[:timeframes].size
      alignment_pct = (bullish_tfs.to_f / total_tfs * 100).round(2)
      base_confidence += (alignment_pct / 10).round(2)

      [[base_confidence, 100].min, 0].max.round(2)
    end
  end
end
