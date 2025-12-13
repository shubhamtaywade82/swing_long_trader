# frozen_string_literal: true

module Screeners
  class LongtermScreener < ApplicationService
    DEFAULT_LIMIT = 10

    def self.call(instruments: nil, limit: nil)
      new(instruments: instruments, limit: limit).call
    end

    def initialize(instruments: nil, limit: nil)
      @instruments = instruments || load_universe
      @limit = limit || DEFAULT_LIMIT
      @config = AlgoConfig.fetch[:long_term_trading] || {}
      @strategy_config = @config[:strategy] || {}
    end

    def call
      candidates = []
      start_time = Time.current
      total_count = @instruments.count
      processed_count = 0
      analyzed_count = 0

      Rails.logger.info("[Screeners::LongtermScreener] Starting screener: #{total_count} instruments, limit: #{@limit}")

      progress_key = "longterm_screener_progress_#{Date.current}"

      # Initialize progress
      Rails.cache.write(progress_key, {
        total: total_count,
        processed: 0,
        analyzed: 0,
        candidates: 0,
        started_at: start_time.iso8601,
        status: "running",
      }, expires_in: 1.hour)

      @instruments.find_each(batch_size: 50) do |instrument|
        processed_count += 1

        # Update progress cache every 10 instruments
        if processed_count % 10 == 0
          elapsed = Time.current - start_time
          rate = begin
            processed_count / elapsed
          rescue StandardError
            0
          end
          remaining = rate > 0 ? (total_count - processed_count) / rate : 0

          Rails.cache.write(progress_key, {
            total: total_count,
            processed: processed_count,
            analyzed: analyzed_count,
            candidates: candidates.size,
            started_at: start_time.iso8601,
            status: "running",
            elapsed: elapsed.round(1),
            remaining: remaining.round(0),
            rate: rate.round(2),
          }, expires_in: 1.hour)

          Rails.logger.info(
            "[Screeners::LongtermScreener] Progress: #{processed_count}/#{total_count} " \
            "(#{analyzed_count} analyzed, #{candidates.size} candidates, " \
            "#{elapsed.round(1)}s elapsed, ~#{remaining.round(0)}s remaining)",
          )
        end

        next unless passes_basic_filters?(instrument)

        instrument_start = Time.current
        analysis = analyze_instrument(instrument)
        instrument_time = Time.current - instrument_start

        # Log slow instruments
        if instrument_time > 3.0
          Rails.logger.warn(
            "[Screeners::LongtermScreener] Slow instrument: #{instrument.symbol} " \
            "took #{instrument_time.round(2)}s",
          )
        end

        next unless analysis

        analyzed_count += 1
        candidates << analysis

        # Cache partial results incrementally (every 3 new candidates)
        # This allows UI to show results as they're found
        if candidates.size % 3 == 0
          # Sort and keep top N candidates
          sorted_candidates = candidates.sort_by { |c| -c[:score] }.first(@limit)

          # Cache partial results
          results_key = "longterm_screener_results_#{Date.current}"
          Rails.cache.write(results_key, sorted_candidates, expires_in: 24.hours)
          Rails.cache.write("#{results_key}_timestamp", Time.current, expires_in: 24.hours)

          # Update progress with current candidate count
          Rails.cache.write(progress_key, {
            total: total_count,
            processed: processed_count,
            analyzed: analyzed_count,
            candidates: sorted_candidates.size,
            started_at: start_time.iso8601,
            status: "running",
            elapsed: (Time.current - start_time).round(1),
            partial_results: true,
          }, expires_in: 1.hour)
        end
      end

      duration = Time.current - start_time

      # Final sort and cache
      sorted_candidates = candidates.sort_by { |c| -c[:score] }.first(@limit)
      results_key = "longterm_screener_results_#{Date.current}"
      Rails.cache.write(results_key, sorted_candidates, expires_in: 24.hours)
      Rails.cache.write("#{results_key}_timestamp", Time.current, expires_in: 24.hours)

      # Mark as completed
      progress_key = "longterm_screener_progress_#{Date.current}"
      Rails.cache.write(progress_key, {
        total: total_count,
        processed: processed_count,
        analyzed: analyzed_count,
        candidates: sorted_candidates.size,
        started_at: start_time.iso8601,
        completed_at: Time.current.iso8601,
        duration: duration.round(1),
        status: "completed",
      }, expires_in: 1.hour)

      Rails.logger.info(
        "[Screeners::LongtermScreener] Completed: #{processed_count} processed, " \
        "#{analyzed_count} analyzed, #{sorted_candidates.size} candidates found in #{duration.round(1)}s",
      )

      # Return sorted top N candidates
      sorted_candidates
    end

    private

    def load_universe
      # Load from IndexConstituent database table (preferred)
      base_scope = if IndexConstituent.exists?
                     universe_symbols = IndexConstituent.distinct.pluck(:symbol).map(&:upcase)
                     Instrument.where(symbol_name: universe_symbols)
                               .or(Instrument.where(isin: IndexConstituent.where.not(isin_code: nil).distinct.pluck(:isin_code).map(&:upcase)))
                   else
                     # Fallback: use all equity/index instruments from NSE
                     Instrument.where(segment: %w[equity index], exchange: "NSE")
                   end

      # Pre-filter instruments that have both daily and weekly candles
      base_scope.joins(:candle_series_records)
                .where(candle_series_records: { timeframe: %w[1D 1W] })
                .group("instruments.id")
                .having("COUNT(DISTINCT candle_series_records.timeframe) = 2")
    end

    def passes_basic_filters?(_instrument)
      # Candles check is already done in load_universe via join
      # No additional filters needed
      true
    end

    def analyze_instrument(instrument)
      # Multi-timeframe analysis (long-term: 1w, 1d, 1h - NO 15m)
      mtf_result = LongTerm::MultiTimeframeAnalyzer.call(
        instrument: instrument,
        include_intraday: @config.dig(:multi_timeframe, :include_intraday) != false,
      )

      return nil unless mtf_result[:success]

      mtf_analysis = mtf_result[:analysis]

      # Load daily and weekly candles for backward compatibility
      daily_series = instrument.load_daily_candles(limit: 200)
      weekly_series = instrument.load_weekly_candles(limit: 52)

      return nil unless daily_series&.candles&.any?
      return nil unless weekly_series&.candles&.any?

      # Need sufficient data
      return nil if daily_series.candles.size < 100
      return nil if weekly_series.candles.size < 20

      # Calculate indicators for both timeframes
      daily_indicators = calculate_indicators(daily_series)
      weekly_indicators = calculate_indicators(weekly_series)

      return nil unless daily_indicators && weekly_indicators

      # Calculate score (enhanced with MTF)
      base_score = calculate_score(daily_series, weekly_series, daily_indicators, weekly_indicators)
      mtf_score = mtf_analysis[:multi_timeframe_score] || 0

      # Combined score: 50% base score, 50% MTF score (more weight to MTF for long-term)
      combined_score = ((base_score * 0.5) + (mtf_score * 0.5)).round(2)

      # Build candidate hash
      {
        instrument_id: instrument.id,
        symbol: instrument.symbol_name,
        score: combined_score,
        base_score: base_score,
        mtf_score: mtf_score,
        daily_indicators: daily_indicators,
        weekly_indicators: weekly_indicators,
        multi_timeframe: mtf_analysis,
        metadata: build_metadata(instrument, daily_series, weekly_series, daily_indicators, weekly_indicators,
                                 mtf_analysis),
      }
    end

    def calculate_indicators(series)
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
      }
    rescue StandardError => e
      Rails.logger.error("[Screeners::LongtermScreener] Indicator calculation failed: #{e.message}")
      nil
    end

    def calculate_supertrend(series)
      st_config = AlgoConfig.fetch.dig(:indicators, :supertrend) || {}
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
      Rails.logger.warn("[Screeners::LongtermScreener] Supertrend calculation failed: #{e.message}")
      nil
    end

    def calculate_score(daily_series, weekly_series, daily_indicators, weekly_indicators)
      score = 0.0
      max_score = 0.0

      # Weekly trend requirement - 40 points
      if @strategy_config.dig(:entry_conditions, :require_weekly_trend)
        if weekly_indicators[:ema20] && weekly_indicators[:ema50] && (weekly_indicators[:ema20] > weekly_indicators[:ema50])
          score += 20
          max_score += 20
        end

        if weekly_indicators[:supertrend] && weekly_indicators[:supertrend][:direction] == :bullish
          score += 20
          max_score += 20
        end
      end

      # Daily trend alignment - 30 points
      if daily_indicators[:ema20] && daily_indicators[:ema50] && (daily_indicators[:ema20] > daily_indicators[:ema50])
        score += 15
        max_score += 15
      end

      if daily_indicators[:ema20] && daily_indicators[:ema200] && (daily_indicators[:ema20] > daily_indicators[:ema200])
        score += 15
        max_score += 15
      end

      # ADX strength (weekly) - 15 points
      if weekly_indicators[:adx]
        if weekly_indicators[:adx] > 25
          score += 15
        elsif weekly_indicators[:adx] > 20
          score += 10
        end
        max_score += 15
      end

      # Momentum score - 15 points
      momentum_score = calculate_momentum_score(daily_series, weekly_series, daily_indicators, weekly_indicators)
      score += momentum_score
      max_score += 15

      # Normalize to 0-100 scale
      max_score.positive? ? (score / max_score * 100).round(2) : 0.0
    end

    def calculate_momentum_score(_daily_series, _weekly_series, daily_indicators, weekly_indicators)
      score = 0.0

      # RSI momentum
      score += 5 if daily_indicators[:rsi] && daily_indicators[:rsi] > 50 && daily_indicators[:rsi] < 70

      score += 5 if weekly_indicators[:rsi] && weekly_indicators[:rsi] > 50 && weekly_indicators[:rsi] < 70

      # MACD momentum
      if daily_indicators[:macd].is_a?(Array) && daily_indicators[:macd].size >= 2
        macd_line = daily_indicators[:macd][0]
        signal_line = daily_indicators[:macd][1]
        score += 5 if macd_line && signal_line && macd_line > signal_line
      end

      score
    end

    def build_metadata(instrument, daily_series, weekly_series, daily_indicators, weekly_indicators, mtf_analysis = nil)
      metadata = {
        ltp: instrument.ltp,
        daily_candles_count: daily_series.candles.size,
        weekly_candles_count: weekly_series.candles.size,
        latest_daily_timestamp: daily_series.candles.last&.timestamp,
        latest_weekly_timestamp: weekly_series.candles.last&.timestamp,
        trend_alignment: check_trend_alignment(daily_indicators, weekly_indicators),
        momentum: calculate_momentum(daily_series, weekly_series, daily_indicators, weekly_indicators),
      }

      # Add multi-timeframe metadata
      if mtf_analysis
        metadata[:multi_timeframe] = {
          score: mtf_analysis[:multi_timeframe_score],
          trend_alignment: mtf_analysis[:trend_alignment],
          momentum_alignment: mtf_analysis[:momentum_alignment],
          timeframes_analyzed: mtf_analysis[:timeframes].keys.map(&:to_s),
          entry_recommendations: mtf_analysis[:entry_recommendations],
        }
      end

      metadata
    end

    def check_trend_alignment(daily_indicators, weekly_indicators)
      alignment = []

      # Weekly alignment
      if weekly_indicators[:ema20] && weekly_indicators[:ema50] && weekly_indicators[:ema20] > weekly_indicators[:ema50]
        alignment << :weekly_ema_bullish
      end

      if weekly_indicators[:supertrend] && weekly_indicators[:supertrend][:direction] == :bullish
        alignment << :weekly_supertrend_bullish
      end

      # Daily alignment
      if daily_indicators[:ema20] && daily_indicators[:ema50] && daily_indicators[:ema20] > daily_indicators[:ema50]
        alignment << :daily_ema_bullish
      end

      alignment
    end

    def calculate_momentum(daily_series, weekly_series, daily_indicators, weekly_indicators)
      daily_closes = daily_series.closes
      weekly_closes = weekly_series.closes

      daily_change = daily_closes.size >= 5 ? ((daily_closes.last - daily_closes[-5]) / daily_closes[-5] * 100).round(2) : nil
      weekly_change = weekly_closes.size >= 4 ? ((weekly_closes.last - weekly_closes[-4]) / weekly_closes[-4] * 100).round(2) : nil

      {
        daily_change_5d: daily_change,
        weekly_change_4w: weekly_change,
        daily_rsi: daily_indicators[:rsi],
        weekly_rsi: weekly_indicators[:rsi],
      }
    end
  end
end
