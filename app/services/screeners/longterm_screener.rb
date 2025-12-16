# frozen_string_literal: true

module Screeners
  class LongtermScreener < ApplicationService
    def self.call(instruments: nil, limit: nil, persist_results: true, screener_run_id: nil)
      new(instruments: instruments, limit: limit, persist_results: persist_results,
          screener_run_id: screener_run_id).call
    end

    def initialize(instruments: nil, limit: nil, persist_results: true, screener_run_id: nil)
      @instruments = instruments || load_universe
      @limit = limit # Remove default limit to screen full universe
      @persist_results = persist_results
      @screener_run_id = screener_run_id
      @config = AlgoConfig.fetch[:long_term_trading] || {}
      @strategy_config = @config[:strategy] || {}
      @candle_cache = {} # Cache candles to avoid N+1 queries
      @analyzed_at = Time.current # Use same timestamp for all results in this run
    end

    def call
      candidates = []
      start_time = Time.current

      # Ensure @instruments is a valid ActiveRecord relation or array
      # If it's a Hash (from incorrect job arguments), convert to nil to use load_universe
      if @instruments.is_a?(Hash)
        Rails.logger.warn("[Screeners::LongtermScreener] Received Hash for instruments, using load_universe instead")
        @instruments = load_universe
      end

      # Ensure we have a valid collection
      unless @instruments.respond_to?(:count) && @instruments.respond_to?(:find_each)
        Rails.logger.error("[Screeners::LongtermScreener] Invalid instruments type: #{@instruments.class}")
        @instruments = load_universe
      end

      # Safely get count, ensuring it's an integer
      # Handle case where count might return unexpected types
      begin
        count_result = @instruments.count
        total_count = if count_result.is_a?(Integer)
                        count_result
                      elsif count_result.is_a?(Numeric)
                        count_result.to_i
                      elsif count_result.is_a?(Hash)
                        Rails.logger.error("[Screeners::LongtermScreener] count returned Hash: #{count_result.inspect}, using load_universe")
                        @instruments = load_universe
                        @instruments.count.to_i
                      else
                        Rails.logger.error("[Screeners::LongtermScreener] Unexpected count type: #{count_result.class} (#{count_result.inspect}), using load_universe")
                        @instruments = load_universe
                        @instruments.count.to_i
                      end
      rescue StandardError => e
        Rails.logger.error("[Screeners::LongtermScreener] Error getting count: #{e.message}, using load_universe")
        @instruments = load_universe
        total_count = @instruments.count.to_i
      end
      processed_count = 0
      analyzed_count = 0

      Rails.logger.info("[Screeners::LongtermScreener] Starting screener: #{total_count} instruments, limit: #{@limit || 'unlimited'}")

      # Preload candles for all instruments to avoid N+1 queries
      preload_candles_for_instruments

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

      # Broadcast initial status
      broadcast_progress(progress_key, {
        total: total_count,
        processed: 0,
        analyzed: 0,
        candidates: 0,
        status: "running",
      })

      @instruments.find_each(batch_size: 50) do |instrument|
        processed_count += 1

        # Update progress cache every 10 instruments
        if processed_count % 10 == 0
          elapsed = Time.current - start_time
          rate = begin
            processed_count.to_f / elapsed.to_f
          rescue StandardError
            0.0
          end
          # Ensure all values are numeric before arithmetic
          total_count_num = total_count.to_f
          processed_count_num = processed_count.to_f
          remaining = rate > 0 && total_count_num > 0 ? ((total_count_num - processed_count_num) / rate) : 0.0

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
            "[Screeners::LongtermScreener] Slow instrument: #{instrument.symbol_name} " \
            "took #{instrument_time.round(2)}s",
          )
        end

        next unless analysis

        analyzed_count += 1
        candidates << analysis

        # Persist result to database immediately (incremental updates)
        persist_result(analysis) if @persist_results

        # Cache and broadcast partial results incrementally (every 3 new candidates)
        # This allows UI to show results as they're found
        if candidates.size % 3 == 0
          # Get top candidates from database if persisting, otherwise from memory
          sorted_candidates = if @persist_results
                                ScreenerResult.latest_for(screener_type: "longterm", limit: @limit)
                                              .map(&:to_candidate_hash)
                              else
                                candidates.sort_by { |c| -c[:score] }.first(@limit || candidates.size)
                              end

          # Cache partial results for backward compatibility
          results_key = "longterm_screener_results_#{Date.current}"
          Rails.cache.write(results_key, sorted_candidates, expires_in: 24.hours)
          Rails.cache.write("#{results_key}_timestamp", Time.current, expires_in: 24.hours)

          # Update progress
          progress_data = {
            total: total_count,
            processed: processed_count,
            analyzed: analyzed_count,
            candidates: sorted_candidates.size,
            started_at: start_time.iso8601,
            status: "running",
            elapsed: (Time.current - start_time).round(1),
            partial_results: true,
          }
          Rails.cache.write(progress_key, progress_data, expires_in: 1.hour)

          # Broadcast progress and partial results via ActionCable
          broadcast_progress(progress_key, progress_data)
          broadcast_partial_results(results_key, sorted_candidates)
        end
      end

      duration = Time.current - start_time

      # Get final results from database if persisting, otherwise from memory
      sorted_candidates = if @persist_results
                            ScreenerResult.latest_for(screener_type: "longterm", limit: @limit)
                                          .map(&:to_candidate_hash)
                          else
                            candidates.sort_by { |c| -c[:score] }.first(@limit || candidates.size)
                          end

      # Cache final results for backward compatibility
      results_key = "longterm_screener_results_#{Date.current}"
      Rails.cache.write(results_key, sorted_candidates, expires_in: 24.hours)
      Rails.cache.write("#{results_key}_timestamp", Time.current, expires_in: 24.hours)

      # Mark as completed
      progress_key = "longterm_screener_progress_#{Date.current}"
      progress_data = {
        total: total_count,
        processed: processed_count,
        analyzed: analyzed_count,
        candidates: sorted_candidates.size,
        started_at: start_time.iso8601,
        completed_at: Time.current.iso8601,
        duration: duration.round(1),
        status: "completed",
      }
      Rails.cache.write(progress_key, progress_data, expires_in: 1.hour)

      # Broadcast completion
      broadcast_progress(progress_key, progress_data)
      broadcast_complete_results(results_key, sorted_candidates)

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
      # NO LIMIT - Screen the complete universe
      # Use table name 'candle_series' directly since CandleSeriesRecord uses custom table_name
      base_scope.joins("INNER JOIN candle_series ON candle_series.instrument_id = instruments.id")
                .where("candle_series.timeframe IN (?)", %w[1D 1W])
                .group("instruments.id")
                .having("COUNT(DISTINCT candle_series.timeframe) = 2")
                .includes(:candle_series_records) # Eager load to reduce queries
    end

    def preload_candles_for_instruments
      # Batch load all daily and weekly candles for all instruments to avoid N+1 queries
      # Safely get count to avoid Hash return from GROUP BY queries
      instrument_count = begin
        count_result = @instruments.count
        if count_result.is_a?(Integer)
          count_result
        elsif count_result.is_a?(Numeric)
          count_result.to_i
        elsif count_result.is_a?(Hash)
          # GROUP BY query returned Hash, use size instead
          @instruments.size
        else
          @instruments.size
        end
      rescue StandardError => e
        Rails.logger.warn("[Screeners::LongtermScreener] Error getting count for preload: #{e.message}, using size")
        @instruments.size
      end
      Rails.logger.info("[Screeners::LongtermScreener] Preloading candles for #{instrument_count} instruments...")

      # Get instrument IDs as a simple array to avoid any relation issues
      # The relation has joins and WHERE clauses referencing candle_series table
      # Execute the full query with all clauses to get the correct IDs
      instrument_ids = if @instruments.is_a?(ActiveRecord::Relation)
                         # Execute the query with all its clauses (joins, WHERE, GROUP BY, HAVING)
                         # to get the correct instrument IDs, then extract just the IDs
                         @instruments.select(:id).to_a.map(&:id)
                       else
                         @instruments.map(&:id)
                       end
      return if instrument_ids.empty?

      # Load all daily and weekly candles in one query
      # Use a completely fresh query to avoid any GROUP BY issues
      all_candle_records = CandleSeriesRecord
                           .where(instrument_id: instrument_ids)
                           .where(timeframe: %w[1D 1W])
                           .order(instrument_id: :asc, timeframe: :asc, timestamp: :desc)
                           .to_a

      # Group candles by instrument_id and timeframe, then take last 200 per group
      candles_by_instrument = all_candle_records
                              .group_by { |r| [r.instrument_id, r.timeframe] }
                              .transform_values { |records| records.take(200) }

      # Build CandleSeries for each instrument
      @instruments.each do |instrument|
        daily_records = candles_by_instrument[[instrument.id, "1D"]] || []
        weekly_records = candles_by_instrument[[instrument.id, "1W"]] || []

        # Build daily series
        if daily_records.any?
          daily_series = CandleSeries.new(symbol: instrument.symbol_name, interval: "1D")
          daily_records.sort_by(&:timestamp).each do |record|
            candle = Candle.new(
              timestamp: record.timestamp,
              open: record.open,
              high: record.high,
              low: record.low,
              close: record.close,
              volume: record.volume,
            )
            daily_series.add_candle(candle)
          end
          # Ensure candles are sorted by timestamp (safety check)
          daily_series.candles.sort_by!(&:timestamp)
          @candle_cache[instrument.id] ||= {}
          @candle_cache[instrument.id]["1D"] = daily_series
        end

        # Build weekly series
        next unless weekly_records.any?

        weekly_series = CandleSeries.new(symbol: instrument.symbol_name, interval: "1W")
        weekly_records.sort_by(&:timestamp).each do |record|
          candle = Candle.new(
            timestamp: record.timestamp,
            open: record.open,
            high: record.high,
            low: record.low,
            close: record.close,
            volume: record.volume,
          )
          weekly_series.add_candle(candle)
        end
        # Ensure candles are sorted by timestamp (safety check)
        weekly_series.candles.sort_by!(&:timestamp)
        @candle_cache[instrument.id] ||= {}
        @candle_cache[instrument.id]["1W"] = weekly_series
      end

      Rails.logger.info("[Screeners::LongtermScreener] Preloaded candles for #{@candle_cache.size} instruments")
    end

    def get_cached_candles(instrument, timeframe)
      cached = @candle_cache[instrument.id]&.[](timeframe)
      return cached if cached

      # Fallback: load if not in cache
      Rails.logger.warn("[Screeners::LongtermScreener] Cache miss for #{instrument.symbol_name} #{timeframe}, loading...")
      case timeframe
      when "1D"
        instrument.load_daily_candles(limit: 200)
      when "1W"
        instrument.load_weekly_candles(limit: 52)
      end
    end

    def persist_result(analysis)
      # Persist each result immediately to database
      # Include setup_status and accumulation_plan in metadata for retrieval
      metadata = (analysis[:metadata] || {}).merge(
        setup_status: analysis[:setup_status],
        setup_reason: analysis[:setup_reason],
        invalidate_if: analysis[:invalidate_if],
        accumulation_conditions: analysis[:accumulation_conditions],
        accumulation_plan: analysis[:accumulation_plan],
        recommendation: analysis[:recommendation],
      )

      ScreenerResult.upsert_result(
        instrument_id: analysis[:instrument_id],
        screener_type: "longterm",
        symbol: analysis[:symbol],
        score: analysis[:score],
        base_score: analysis[:base_score] || 0,
        mtf_score: analysis[:mtf_score] || 0,
        indicators: (analysis[:daily_indicators] || {}).merge(weekly_indicators: analysis[:weekly_indicators] || {}),
        metadata: metadata,
        multi_timeframe: analysis[:multi_timeframe] || {},
        screener_run_id: @screener_run_id,
        stage: "screener",
        analyzed_at: @analyzed_at,
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::LongtermScreener] Failed to persist result for #{analysis[:symbol]}: #{e.message}")
      # Don't fail the entire screener if one save fails
    end

    def broadcast_progress(_progress_key, progress_data)
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "screener_progress",
          screener_type: "longterm",
          progress: progress_data,
        },
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::LongtermScreener] Failed to broadcast progress: #{e.message}")
    end

    def broadcast_partial_results(_results_key, candidates)
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "screener_partial_results",
          screener_type: "longterm",
          candidate_count: candidates.size,
          candidates: candidates.first(20), # Send top 20 for progressive display
        },
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::LongtermScreener] Failed to broadcast partial results: #{e.message}")
    end

    def broadcast_complete_results(_results_key, candidates)
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "screener_complete",
          screener_type: "longterm",
          candidate_count: candidates.size,
          message: "Long-term screener completed successfully",
        },
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::LongtermScreener] Failed to broadcast completion: #{e.message}")
    end

    def passes_basic_filters?(_instrument)
      # Candles check is already done in load_universe via join
      # No additional filters needed
      true
    end

    def analyze_instrument(instrument)
      # Use cached candles to avoid N+1 queries
      daily_series = get_cached_candles(instrument, "1D")
      weekly_series = get_cached_candles(instrument, "1W")

      return nil unless daily_series&.candles&.any?
      return nil unless weekly_series&.candles&.any?

      # Need sufficient data
      return nil if daily_series.candles.size < 100
      return nil if weekly_series.candles.size < 20

      # Multi-timeframe analysis (long-term: 1w, 1d, 1h - NO 15m)
      mtf_result = LongTerm::MultiTimeframeAnalyzer.call(
        instrument: instrument,
        include_intraday: @config.dig(:multi_timeframe, :include_intraday) != false,
        cached_candles: @candle_cache,
      )

      return nil unless mtf_result[:success]

      mtf_analysis = mtf_result[:analysis]

      # Calculate indicators for both timeframes
      daily_indicators = calculate_indicators(daily_series)
      weekly_indicators = calculate_indicators(weekly_series)

      return nil unless daily_indicators && weekly_indicators

      # Calculate score (enhanced with MTF)
      base_score = calculate_score(daily_series, weekly_series, daily_indicators, weekly_indicators)
      mtf_score = mtf_analysis[:multi_timeframe_score] || 0

      # Combined score: 50% base score, 50% MTF score (more weight to MTF for long-term)
      combined_score = ((base_score * 0.5) + (mtf_score * 0.5)).round(2)

      # Build initial candidate hash
      candidate = {
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

      # CRITICAL: Determine accumulation setup status (ACCUMULATE vs WAIT vs NOT_READY)
      # This is the decision layer that separates "bullish" from "accumulation-ready"
      setup_result = Screeners::LongtermSetupDetector.call(
        candidate: candidate,
        daily_series: daily_series,
        weekly_series: weekly_series,
        daily_indicators: daily_indicators,
        weekly_indicators: weekly_indicators,
        mtf_analysis: mtf_analysis,
        portfolio: nil, # Portfolio available in later layers
      )

      candidate[:setup_status] = setup_result[:status]
      candidate[:setup_reason] = setup_result[:reason]
      candidate[:invalidate_if] = setup_result[:invalidate_if]
      candidate[:accumulation_conditions] = setup_result[:accumulation_conditions]

      # Generate accumulation plan for ACCUMULATE setups only
      if setup_result[:status] == Screeners::LongtermSetupDetector::ACCUMULATE
        accumulation_plan = Screeners::LongtermTradePlanBuilder.call(
          candidate: candidate,
          daily_series: daily_series,
          weekly_series: weekly_series,
          daily_indicators: daily_indicators,
          weekly_indicators: weekly_indicators,
          setup_status: setup_result,
          portfolio: nil, # Will use default calculation, enhanced later with portfolio
        )

        if accumulation_plan
          candidate[:accumulation_plan] = accumulation_plan
          # Update recommendation to be actionable
          candidate[:recommendation] = build_actionable_recommendation(accumulation_plan, setup_result)
        else
          # Plan generation failed
          candidate[:setup_status] = Screeners::LongtermSetupDetector::NOT_READY
          candidate[:setup_reason] = "Accumulation conditions not met"
          candidate[:recommendation] = "NOT READY: Accumulation conditions not optimal"
        end
      else
        # Not ready - provide guidance
        candidate[:recommendation] = build_wait_recommendation(setup_result)
      end

      candidate
    end

    def build_actionable_recommendation(accumulation_plan, _setup_result)
      "ACCUMULATE #{accumulation_plan[:buy_zone]}, Invalid: ₹#{accumulation_plan[:invalid_level]}, " \
        "Horizon: #{accumulation_plan[:time_horizon]} months, Allocation: #{accumulation_plan[:allocation_pct]}%"
    end

    def build_wait_recommendation(setup_result)
      case setup_result[:status]
      when Screeners::LongtermSetupDetector::WAIT_DIP
        "WAIT: #{setup_result[:reason]}"
      when Screeners::LongtermSetupDetector::WAIT_BREAKOUT
        "WAIT: #{setup_result[:reason]}"
      when Screeners::LongtermSetupDetector::IN_POSITION
        "Already in position - Monitor"
      when Screeners::LongtermSetupDetector::NOT_READY
        "NOT READY: #{setup_result[:reason]}"
      else
        "WAIT: #{setup_result[:reason]}"
      end
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
        latest_close: series.latest_close,
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
        latest_daily_timestamp: daily_series.latest_candle&.timestamp,
        latest_weekly_timestamp: weekly_series.latest_candle&.timestamp,
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

      # Ensure we have numeric values (defensive programming)
      daily_closes = daily_closes.map do |c|
        if c.is_a?(Numeric)
          c
        else
          (c.respond_to?(:to_f) ? c.to_f : nil)
        end
      end.compact
      weekly_closes = weekly_closes.map do |c|
        if c.is_a?(Numeric)
          c
        else
          (c.respond_to?(:to_f) ? c.to_f : nil)
        end
      end.compact

      daily_change = if daily_closes.size >= 5 && daily_closes.last.is_a?(Numeric) && daily_closes[-5].is_a?(Numeric) && daily_closes[-5] != 0
                       ((daily_closes.last - daily_closes[-5]) / daily_closes[-5] * 100).round(2)
                     else
                       nil
                     end

      weekly_change = if weekly_closes.size >= 4 && weekly_closes.last.is_a?(Numeric) && weekly_closes[-4].is_a?(Numeric) && weekly_closes[-4] != 0
                        ((weekly_closes.last - weekly_closes[-4]) / weekly_closes[-4] * 100).round(2)
                      else
                        nil
                      end

      {
        daily_change_5d: daily_change,
        weekly_change_4w: weekly_change,
        daily_rsi: daily_indicators[:rsi],
        weekly_rsi: weekly_indicators[:rsi],
      }
    end
  end
end
