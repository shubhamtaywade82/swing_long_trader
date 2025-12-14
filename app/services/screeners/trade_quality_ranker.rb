# frozen_string_literal: true

module Screeners
  # Layer 2: Trade Quality Scoring
  # Reduces 100-150 bullish candidates → 30-40 high-quality setups
  #
  # Scores candidates on:
  # - Trend Quality (25 points)
  # - Structure Quality (20 points)
  # - Location Quality (20 points)
  # - Volatility Quality (15 points)
  # - Liquidity (10 points)
  # - Risk-Reward Potential (10 points)
  class TradeQualityRanker < ApplicationService
    DEFAULT_TOP_LIMIT = 40

    def self.call(candidates:, limit: nil)
      new(candidates: candidates, limit: limit).call
    end

    def initialize(candidates:, limit: nil)
      @candidates = candidates
      @limit = limit || DEFAULT_TOP_LIMIT
      @config = AlgoConfig.fetch(%i[swing_trading trade_quality]) || {}
    end

    def call
      return [] if @candidates.empty?

      ranked = @candidates.map do |candidate|
        quality_score = calculate_quality_score(candidate)
        candidate.merge(
          trade_quality_score: quality_score[:total],
          trade_quality_breakdown: quality_score[:breakdown],
          trade_quality_rank: nil, # Will be set after sorting
        )
      end

      # Sort by quality score and take top N
      sorted = ranked.sort_by { |c| -c[:trade_quality_score] }.first(@limit)
      sorted.each_with_index do |candidate, index|
        candidate[:trade_quality_rank] = index + 1
      end

      sorted
    end

    private

    def calculate_quality_score(candidate)
      indicators = candidate[:indicators] || {}
      metadata = candidate[:metadata] || {}
      mtf_data = candidate[:multi_timeframe] || {}
      series_data = extract_series_data(candidate)

      breakdown = {
        trend_quality: score_trend_quality(indicators, mtf_data),
        structure_quality: score_structure_quality(series_data, mtf_data, metadata),
        location_quality: score_location_quality(series_data, indicators, metadata),
        volatility_quality: score_volatility_quality(indicators, metadata),
        liquidity: score_liquidity(indicators, metadata),
        risk_reward: score_risk_reward(series_data, indicators, metadata),
      }

      total = breakdown.values.sum.round(2)

      {
        total: total,
        breakdown: breakdown,
      }
    end

    def extract_series_data(candidate)
      # Extract price and structure data from candidate
      indicators = candidate[:indicators] || {}
      metadata = candidate[:metadata] || {}

      {
        latest_close: indicators[:latest_close] || metadata[:ltp],
        ema20: indicators[:ema20],
        ema50: indicators[:ema50],
        ema200: indicators[:ema200],
        atr: indicators[:atr],
        supertrend: indicators[:supertrend],
      }
    end

    # Trend Quality: 25 points
    # - EMA alignment strength (20 > 50 > 200 distance)
    # - Weekly + Daily alignment (extra weight)
    def score_trend_quality(indicators, mtf_data)
      score = 0.0
      max_score = 25.0

      ema20 = indicators[:ema20]
      ema50 = indicators[:ema50]
      ema200 = indicators[:ema200]

      # Basic EMA alignment (15 points)
      if ema20 && ema50 && ema200
        # Check 20 > 50 > 200 alignment
        if ema20 > ema50 && ema50 > ema200
          # Calculate distance strength
          distance_20_50 = ((ema20 - ema50) / ema50 * 100).abs
          distance_50_200 = ((ema50 - ema200) / ema200 * 100).abs

          # Strong alignment: > 2% separation
          if distance_20_50 > 2.0 && distance_50_200 > 2.0
            score += 15
          # Moderate alignment: > 1% separation
          elsif distance_20_50 > 1.0 && distance_50_200 > 1.0
            score += 10
          # Weak alignment: still aligned
          else
            score += 5
          end
        # Partial alignment: 20 > 50 but not 50 > 200
        elsif ema20 > ema50
          score += 5
        end
      end

      # Multi-timeframe alignment (10 points)
      if mtf_data[:trend_alignment]
        ta = mtf_data[:trend_alignment]
        if ta[:aligned] && ta[:bullish_count] >= 3
          score += 10
        elsif ta[:aligned] && ta[:bullish_count] >= 2
          score += 5
        end
      end

      [score, max_score].min.round(2)
    end

    # Structure Quality: 20 points
    # - Fresh BOS vs old trend
    # - HH-HL sequence count
    # - Distance from last demand zone
    def score_structure_quality(series_data, mtf_data, metadata)
      score = 0.0
      max_score = 20.0

      # Check SMC validation if available
      smc_validation = metadata[:smc_validation]
      if smc_validation && smc_validation[:valid]
        score += 10
        score += smc_validation[:score].to_f if smc_validation[:score]
      end

      # Check multi-timeframe structure
      if mtf_data[:structure]
        # Prefer fresh breakouts (recent BOS)
        structure = mtf_data[:structure]
        if structure[:bos] && structure[:bos][:type] == :bullish
          # Recent BOS (within last 10 candles) gets higher score
          bos_age = structure[:bos][:age] || 0
          if bos_age <= 10
            score += 10
          elsif bos_age <= 20
            score += 5
          end
        end
      end

      # Check for HH-HL pattern in metadata
      if metadata[:structure_pattern] == "HH-HL"
        score += 5
      end

      [score, max_score].min.round(2)
    end

    # Location Quality: 20 points (CRITICAL)
    # - Near breakout? (ideal)
    # - Near retest of demand? (good)
    # - NOT extended 10-15% above structure (avoid)
    def score_location_quality(series_data, indicators, metadata)
      score = 0.0
      max_score = 20.0

      latest_close = series_data[:latest_close]
      ema20 = series_data[:ema20]
      ema50 = series_data[:ema50]
      supertrend = series_data[:supertrend]

      return 0 unless latest_close

      # Check distance from EMAs (ideal: near EMA20, not too far from EMA50)
      if ema20 && ema50
        distance_from_ema20 = ((latest_close - ema20) / ema20 * 100).abs
        distance_from_ema50 = ((latest_close - ema50) / ema50 * 100).abs

        # Ideal: within 2% of EMA20 (fresh pullback)
        if distance_from_ema20 <= 2.0
          score += 10
        # Good: within 5% of EMA20
        elsif distance_from_ema20 <= 5.0
          score += 7
        # Acceptable: within 10% of EMA50
        elsif distance_from_ema50 <= 10.0
          score += 5
        end

        # Penalize if extended > 10% above EMA20
        if distance_from_ema20 > 10.0
          score -= 5
        end
      end

      # Check supertrend distance
      if supertrend && supertrend[:value]
        st_value = supertrend[:value]
        distance_from_st = ((latest_close - st_value) / st_value * 100).abs

        # Ideal: within 3% of supertrend line
        if distance_from_st <= 3.0
          score += 5
        # Good: within 5%
        elsif distance_from_st <= 5.0
          score += 3
        end
      end

      # Check momentum metadata for extension warning
      momentum = metadata[:momentum]
      if momentum && momentum[:change_5d]
        # Penalize if run up > 15% in 5 days (extended)
        if momentum[:change_5d] > 15.0
          score -= 10
        # Penalize if run up > 10% in 5 days
        elsif momentum[:change_5d] > 10.0
          score -= 5
        end
      end

      [score, max_score].min.round(2)
    end

    # Volatility Quality: 15 points
    # - ATR % of price (ideal: 2-5%)
    # - Avoid too low (dead stocks) or too high (news-driven)
    def score_volatility_quality(indicators, metadata)
      score = 0.0
      max_score = 15.0

      volatility = metadata[:volatility]
      return 0 unless volatility

      atr_percent = volatility[:atr_percent]
      return 0 unless atr_percent

      # Ideal range: 2-5%
      if atr_percent >= 2.0 && atr_percent <= 5.0
        score = 15.0
      # Good range: 1.5-6%
      elsif atr_percent >= 1.5 && atr_percent <= 6.0
        score = 10.0
      # Acceptable: 1-7%
      elsif atr_percent >= 1.0 && atr_percent <= 7.0
        score = 5.0
      # Too low (dead stock) or too high (news-driven)
      else
        score = 0.0
      end

      score.round(2)
    end

    # Liquidity: 10 points
    # - Avg volume threshold
    # - Avoid low participation moves
    def score_liquidity(indicators, metadata)
      score = 0.0
      max_score = 10.0

      volume = indicators[:volume] || {}
      volume_metrics = volume.is_a?(Hash) ? volume : {}

      latest_volume = volume_metrics[:latest] || 0
      avg_volume = volume_metrics[:average] || 0

      return 0 if avg_volume.zero?

      # Check volume spike ratio
      spike_ratio = volume_metrics[:spike_ratio] || (latest_volume.to_f / avg_volume)

      # Strong participation: > 1.5x average
      if spike_ratio >= 1.5
        score = 10.0
      # Good participation: > 1.2x average
      elsif spike_ratio >= 1.2
        score = 7.0
      # Acceptable: > 1.0x average
      elsif spike_ratio >= 1.0
        score = 5.0
      # Low participation: < 1.0x average
      else
        score = 2.0
      end

      score.round(2)
    end

    # Risk-Reward Potential: 10 points
    # - Can this setup give ≥ 2.5R?
    # - If RR < 2 → downrank heavily
    def score_risk_reward(series_data, indicators, metadata)
      score = 0.0
      max_score = 10.0

      latest_close = series_data[:latest_close]
      ema20 = series_data[:ema20]
      ema50 = series_data[:ema50]
      atr = series_data[:atr]

      return 0 unless latest_close && atr

      # Estimate entry (current price or pullback to EMA20)
      entry_price = latest_close
      if ema20 && latest_close > ema20
        # If extended, assume entry on pullback to EMA20
        entry_price = ema20
      end

      # Estimate stop loss (below EMA50 or 2 ATR below entry)
      stop_loss = if ema50 && entry_price > ema50
                    ema50 * 0.98 # 2% below EMA50
                  else
                    entry_price - (atr * 2) # 2 ATR below entry
                  end

      # Estimate take profit (2.5R minimum, or resistance at EMA extension)
      risk = (entry_price - stop_loss).abs
      return 0 if risk.zero?

      # Target: 2.5R minimum
      target_price = entry_price + (risk * 2.5)

      # Check if target is reasonable (not > 15% above current)
      distance_to_target = ((target_price - latest_close) / latest_close * 100).abs

      # If target is within 15% of current, it's achievable
      if distance_to_target <= 15.0
        # Calculate actual RR
        reward = (target_price - entry_price).abs
        rr_ratio = reward / risk

        # Score based on RR
        if rr_ratio >= 3.0
          score = 10.0
        elsif rr_ratio >= 2.5
          score = 8.0
        elsif rr_ratio >= 2.0
          score = 5.0
        else
          # RR < 2: downrank heavily
          score = 0.0
        end
      else
        # Target too far, likely not achievable
        score = 2.0
      end

      score.round(2)
    end
  end
end
