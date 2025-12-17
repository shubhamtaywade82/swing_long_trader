# frozen_string_literal: true

module Screeners
  class SwingScreener < ApplicationService
    DEFAULT_LIMIT = 50

    def self.call(instruments: nil, limit: nil, persist_results: true, screener_run_id: nil)
      new(instruments: instruments, limit: limit, persist_results: persist_results,
          screener_run_id: screener_run_id).call
    end

    def initialize(instruments: nil, limit: nil, persist_results: true, screener_run_id: nil)
      @instruments = instruments || load_universe
      @limit = limit # Remove default limit to screen full universe
      @persist_results = persist_results
      @screener_run_id = screener_run_id
      @config = AlgoConfig.fetch[:swing_trading] || {}
      @screening_config = @config[:screening] || {}
      @strategy_config = @config[:strategy] || {}
      @candle_cache = {} # Cache candles to avoid N+1 queries
      @analyzed_at = Time.current # Use same timestamp for all results in this run
    end

    def call
      # Ensure candles are fresh before screening
      # This checks if daily candles are up-to-date and triggers ingestion if stale
      freshness_result = Candles::FreshnessChecker.ensure_fresh(
        timeframe: :daily,
        auto_ingest: !Rails.env.test?, # Auto-ingest in production, skip in tests
      )
      unless freshness_result[:fresh]
        Rails.logger.warn(
          "[Screeners::SwingScreener] Starting with stale candles: " \
          "#{freshness_result[:freshness_percentage]&.round(1)}% fresh. " \
          "Ingestion #{freshness_result[:ingested] ? 'triggered' : 'skipped'}.",
        )
      end

      candidates = []
      start_time = Time.current
      total_count = @instruments.count
      processed_count = 0
      analyzed_count = 0
      progress_key = "swing_screener_progress_#{Date.current}"

      Rails.logger.info("[Screeners::SwingScreener] Starting screener: #{total_count} instruments, limit: #{@limit}")

      # Preload candles for all instruments to avoid N+1 queries
      preload_candles_for_instruments

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
            "[Screeners::SwingScreener] Progress: #{processed_count}/#{total_count} " \
            "(#{analyzed_count} analyzed, #{candidates.size} candidates, " \
            "#{elapsed.round(1)}s elapsed, ~#{remaining.round(0)}s remaining)",
          )
        end

        next unless passes_basic_filters?(instrument)

        instrument_start = Time.current
        analysis = analyze_instrument(instrument)
        instrument_time = Time.current - instrument_start

        # Log slow instruments
        if instrument_time > 2.0
          Rails.logger.warn(
            "[Screeners::SwingScreener] Slow instrument: #{instrument.symbol_name} " \
            "took #{instrument_time.round(2)}s",
          )
        end

        next unless analysis

        analyzed_count += 1
        candidates << analysis

        # Persist result to database immediately (incremental updates)
        # Use transaction to ensure data consistency before broadcast
        if @persist_results
          ActiveRecord::Base.transaction do
            persist_result(analysis)
          end
        end

        # Broadcast individual record update immediately for live UI updates
        # Only broadcast after successful persistence
        broadcast_record_added(analysis, {
          total: total_count,
          processed: processed_count,
          analyzed: analyzed_count,
          candidates: candidates.size,
          started_at: start_time.iso8601,
          status: "running",
          elapsed: (Time.current - start_time).round(1),
          screener_run_id: @screener_run_id,
          stage: "screener",
        })

        # Cache and broadcast aggregated results incrementally (every 5 new candidates)
        # This allows UI to show top candidates list
        if candidates.size % 5 == 0
          # Get top candidates from database if persisting, otherwise from memory
          sorted_candidates = if @persist_results
                                ScreenerResult.latest_for(screener_type: "swing", limit: @limit)
                                              .map(&:to_candidate_hash)
                              else
                                candidates.sort_by { |c| -c[:score] }.first(@limit || candidates.size)
                              end

          # Cache partial results for backward compatibility
          results_key = "swing_screener_results_#{Date.current}"
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
                            ScreenerResult.latest_for(screener_type: "swing", limit: @limit)
                                          .map(&:to_candidate_hash)
                          else
                            candidates.sort_by { |c| -c[:score] }.first(@limit || candidates.size)
                          end

      # Cache final results for backward compatibility
      results_key = "swing_screener_results_#{Date.current}"
      Rails.cache.write(results_key, sorted_candidates, expires_in: 24.hours)
      Rails.cache.write("#{results_key}_timestamp", Time.current, expires_in: 24.hours)

      # Mark as completed
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
        "[Screeners::SwingScreener] Completed: #{processed_count} processed, " \
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

      # Pre-filter instruments that have daily candles to avoid N+1 queries
      # Use distinct to avoid duplicates from joins
      # NO LIMIT - Screen the complete universe
      base_scope.joins(:candle_series_records)
                .where(candle_series_records: { timeframe: :daily })
                .distinct
                .includes(:candle_series_records) # Eager load to reduce queries
    end

    def preload_candles_for_instruments
      # Batch load all daily candles for all instruments to avoid N+1 queries
      Rails.logger.info("[Screeners::SwingScreener] Preloading candles for #{@instruments.count} instruments...")

      instrument_ids = @instruments.pluck(:id)

      # Load all daily candles in one query
      candle_records = CandleSeriesRecord
                       .for_timeframe(:daily)
                       .where(instrument_id: instrument_ids)
                       .recent(100) # Get last 100 candles per instrument
                       .order(instrument_id: :asc, timestamp: :desc)
                       .to_a

      # Group candles by instrument_id
      candles_by_instrument = candle_records.group_by(&:instrument_id)

      # Build CandleSeries for each instrument
      @instruments.each do |instrument|
        records = candles_by_instrument[instrument.id] || []
        next if records.empty?

        # Convert to CandleSeries format
        series = CandleSeries.new(
          symbol: instrument.symbol_name,
          interval: CandleSeriesRecord.timeframe_to_interval(:daily),
        )

        # Sort by timestamp (oldest first) and convert to Candle objects
        records.sort_by(&:timestamp).each do |record|
          candle = Candle.new(
            timestamp: record.timestamp,
            open: record.open,
            high: record.high,
            low: record.low,
            close: record.close,
            volume: record.volume,
          )
          series.add_candle(candle)
        end

        # Ensure candles are sorted by timestamp (safety check)
        series.candles.sort_by!(&:timestamp)

        @candle_cache[instrument.id] ||= {}
        @candle_cache[instrument.id][:daily] = series
      end

      Rails.logger.info("[Screeners::SwingScreener] Preloaded candles for #{@candle_cache.size} instruments")
    end

    def get_cached_candles(instrument, timeframe)
      cached = @candle_cache[instrument.id]&.[](timeframe)
      return cached if cached

      # Fallback: load if not in cache (shouldn't happen if preload worked)
      Rails.logger.warn("[Screeners::SwingScreener] Cache miss for #{instrument.symbol_name} #{timeframe}, loading...")
      instrument.load_daily_candles(limit: 100)
    end

    def broadcast_progress(_progress_key, progress_data)
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "screener_progress",
          screener_type: "swing",
          progress: progress_data,
        },
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::SwingScreener] Failed to broadcast progress: #{e.message}")
    end

    def broadcast_partial_results(_results_key, candidates)
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "screener_partial_results",
          screener_type: "swing",
          candidate_count: candidates.size,
          candidates: candidates.first(20), # Send top 20 for progressive display
        },
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::SwingScreener] Failed to broadcast partial results: #{e.message}")
    end

    def broadcast_complete_results(_results_key, candidates)
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "screener_complete",
          screener_type: "swing",
          candidate_count: candidates.size,
          message: "Swing screener completed successfully",
        },
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::SwingScreener] Failed to broadcast completion: #{e.message}")
    end

    def broadcast_record_added(analysis, progress_data)
      # Broadcast individual record for live table updates
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "screener_record_added",
          screener_type: "swing",
          screener_run_id: progress_data[:screener_run_id],
          stage: progress_data[:stage] || "screener",
          record: analysis,
          progress: progress_data,
        },
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::SwingScreener] Failed to broadcast record: #{e.message}")
    end

    def passes_basic_filters?(instrument)
      # Candles check is already done in load_universe via join
      # Just check price range (if LTP available)

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
      # Use cached candles to avoid N+1 queries
      daily_series = get_cached_candles(instrument, :daily)
      return nil unless daily_series&.candles&.any?

      # Multi-timeframe analysis (DISABLE intraday by default for performance)
      # Intraday fetching makes API calls which are very slow
      # Only enable if explicitly configured
      include_intraday = @config.dig(:multi_timeframe, :include_intraday) == true

      # Pass cached candles to MTF analyzer to avoid reloading
      mtf_result = Swing::MultiTimeframeAnalyzer.call(
        instrument: instrument,
        include_intraday: include_intraday,
        cached_candles: @candle_cache,
      )

      return nil unless mtf_result[:success]

      mtf_analysis = mtf_result[:analysis]

      # Need at least 50 candles for reliable analysis
      return nil if daily_series.candles.size < 50

      # Calculate indicators (from daily for backward compatibility)
      indicators = calculate_indicators(daily_series)
      return nil unless indicators

      # Calculate score based on filters (enhanced with MTF)
      base_score = calculate_score(daily_series, indicators)
      mtf_score = mtf_analysis[:multi_timeframe_score] || 0

      # Combined score: 60% base score, 40% MTF score
      combined_score = ((base_score * 0.6) + (mtf_score * 0.4)).round(2)

      # Validate SMC structure (optional)
      smc_validation = validate_smc_structure(daily_series, indicators)

      # Build initial candidate hash
      # SCREENER CONTRACT: Only candidate generation data, no setup status, no trade plans, no recommendations
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

      # SCREENER CONTRACT: Setup classification and trade planning happen in later layers
      # - SetupDetector is called by TradeQualityRanker or SetupClassifier service
      # - TradePlanBuilder is called by TradePlanner service
      # - Recommendations are generated by FinalSelector or TradePlanner
    end

    # SCREENER CONTRACT: Recommendation building removed - belongs to later layers

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
        latest_close: series.latest_close,
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
      if @strategy_config.dig(:trend_filters, :use_ema20) &&
         @strategy_config.dig(:trend_filters, :use_ema50) &&
         indicators[:ema20] && indicators[:ema50] && (indicators[:ema20] > indicators[:ema50])
        score += 15
        max_score += 15
      end

      if @strategy_config.dig(:trend_filters, :use_ema200) &&
         indicators[:ema20] && indicators[:ema200] && (indicators[:ema20] > indicators[:ema200])
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
        latest_timestamp: series.latest_candle&.timestamp,
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
      direction = if indicators[:supertrend] && indicators[:supertrend][:direction] == :bearish
                    :short
                  else
                    :long # Default or bullish
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

    def persist_result(analysis)
      # SCREENER CONTRACT: Only persist candidate generation data
      # Remove any forbidden fields (setup_status, trade_plan, recommendation, etc.)
      clean_metadata = (analysis[:metadata] || {}).dup
      clean_metadata.delete(:setup_status)
      clean_metadata.delete(:setup_reason)
      clean_metadata.delete(:invalidate_if)
      clean_metadata.delete(:entry_conditions)
      clean_metadata.delete(:trade_plan)
      clean_metadata.delete(:accumulation_plan)
      clean_metadata.delete(:recommendation)

      ScreenerResult.upsert_result(
        instrument_id: analysis[:instrument_id],
        screener_type: "swing",
        symbol: analysis[:symbol],
        score: analysis[:score],
        base_score: analysis[:base_score] || 0,
        mtf_score: analysis[:mtf_score] || 0,
        indicators: analysis[:indicators] || {},
        metadata: clean_metadata,
        multi_timeframe: analysis[:multi_timeframe] || {},
        screener_run_id: @screener_run_id,
        stage: "screener",
        analyzed_at: @analyzed_at,
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::SwingScreener] Failed to persist result for #{analysis[:symbol]}: #{e.message}")
      # Don't fail the entire screener if one save fails
    end
  end
end
