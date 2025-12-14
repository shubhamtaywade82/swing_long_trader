# frozen_string_literal: true

module Screeners
  # Layer 4: Portfolio & Capacity Filter
  # Reduces 10-15 AI-approved candidates → 3-5 tradable positions
  #
  # Applies portfolio constraints:
  # - Max open positions (3-5)
  # - Max capital per trade (10-15% of equity)
  # - Sector exposure limit (max 2 per sector)
  # - Correlation filter (avoid overcrowding)
  class FinalSelector < ApplicationService
    DEFAULT_SWING_LIMIT = 5
    DEFAULT_LONGTERM_LIMIT = 5
    DEFAULT_MAX_POSITIONS = 5
    DEFAULT_MAX_CAPITAL_PCT = 15.0
    DEFAULT_MAX_PER_SECTOR = 2

    def self.call(swing_candidates: [], longterm_candidates: [], swing_limit: nil, longterm_limit: nil, portfolio: nil)
      new(
        swing_candidates: swing_candidates,
        longterm_candidates: longterm_candidates,
        swing_limit: swing_limit,
        longterm_limit: longterm_limit,
        portfolio: portfolio,
      ).call
    end

    def initialize(swing_candidates: [], longterm_candidates: [], swing_limit: nil, longterm_limit: nil, portfolio: nil)
      @swing_candidates = swing_candidates
      @longterm_candidates = longterm_candidates
      @swing_limit = swing_limit || DEFAULT_SWING_LIMIT
      @longterm_limit = longterm_limit || DEFAULT_LONGTERM_LIMIT
      @portfolio = portfolio || load_default_portfolio
      @config = AlgoConfig.fetch(%i[swing_trading final_selection]) || {}
    end

    def call
      {
        swing: select_swing_candidates,
        longterm: select_longterm_candidates,
        summary: build_summary,
        tiers: build_tiers,
      }
    end

    private

    def load_default_portfolio
      # Try to find active portfolio (paper or live)
      CapitalAllocationPortfolio.active.first || nil
    end

    def select_swing_candidates
      return [] if @swing_candidates.empty?

      # Get portfolio constraints
      constraints = get_portfolio_constraints

      # Rank candidates by combined score
      ranked = rank_candidates(@swing_candidates)

      # Apply portfolio filters
      selected = []
      sector_counts = {}
      current_positions = get_current_positions

      ranked.each do |candidate|
        # Check max positions limit
        break if selected.size >= constraints[:max_positions]

        # Check sector limit
        sector = get_sector(candidate)
        if sector && sector_counts[sector].to_i >= constraints[:max_per_sector]
          next
        end

        # Check capital availability
        if !has_sufficient_capital?(candidate, constraints)
          next
        end

        # Check correlation (avoid too many similar stocks)
        if too_correlated?(candidate, selected, constraints)
          next
        end

        # Passed all filters
        selected << candidate.merge(
          tier: determine_tier(candidate, selected.size),
          sector: sector,
        )

        sector_counts[sector] = (sector_counts[sector] || 0) + 1 if sector
      end

      # Set ranks
      selected.each_with_index do |candidate, index|
        candidate[:rank] = index + 1
      end

      selected
    end

    def rank_candidates(candidates)
      candidates.map do |candidate|
        # Combine all scores
        screener_score = candidate[:score] || 0
        quality_score = candidate[:trade_quality_score] || 0
        ai_confidence = candidate[:ai_confidence] || 0

        # Weighted combination:
        # - 30% screener score (technical eligibility)
        # - 40% trade quality score (Layer 2)
        # - 30% AI confidence (Layer 3)
        combined_score = (
          (screener_score * 0.3) +
          (quality_score * 0.4) +
          (ai_confidence * 10.0 * 0.3) # Convert 0-10 scale to 0-100
        ).round(2)

        candidate.merge(combined_score: combined_score)
      end.sort_by { |c| -c[:combined_score] }
    end

    def get_portfolio_constraints
      if @portfolio&.swing_risk_config
        risk_config = @portfolio.swing_risk_config
        {
          max_positions: risk_config.max_open_positions || DEFAULT_MAX_POSITIONS,
          max_capital_pct: risk_config.max_position_exposure || DEFAULT_MAX_CAPITAL_PCT,
          max_per_sector: @config[:max_per_sector] || DEFAULT_MAX_PER_SECTOR,
          total_equity: @portfolio.total_equity || 100_000,
        }
      else
        {
          max_positions: @config[:max_positions] || DEFAULT_MAX_POSITIONS,
          max_capital_pct: @config[:max_capital_pct] || DEFAULT_MAX_CAPITAL_PCT,
          max_per_sector: @config[:max_per_sector] || DEFAULT_MAX_PER_SECTOR,
          total_equity: @portfolio&.total_equity || 100_000,
        }
      end
    end

    def get_current_positions
      return [] unless @portfolio

      @portfolio.open_swing_positions.includes(:instrument).map do |pos|
        {
          symbol: pos.instrument&.symbol_name || pos.symbol,
          sector: get_sector_for_instrument(pos.instrument),
        }
      end
    end

    def get_sector(candidate)
      return nil unless candidate[:instrument_id]

      instrument = Instrument.find_by(id: candidate[:instrument_id])
      get_sector_for_instrument(instrument)
    end

    def get_sector_for_instrument(instrument)
      return nil unless instrument

      # Try to get sector from IndexConstituent
      constituent = IndexConstituent.find_by(symbol: instrument.symbol_name.upcase)
      return constituent.industry if constituent&.industry.present?

      # Fallback: try ISIN match
      if instrument.isin.present?
        constituent = IndexConstituent.find_by(isin_code: instrument.isin.upcase)
        return constituent.industry if constituent&.industry.present?
      end

      nil
    end

    def has_sufficient_capital?(candidate, constraints)
      return true unless @portfolio

      # Estimate position size (10-15% of equity)
      max_position_value = constraints[:total_equity] * (constraints[:max_capital_pct] / 100.0)

      # Check available capital
      available = @portfolio.available_swing_capital || @portfolio.swing_capital || 0

      available >= max_position_value * 0.5 # Require at least 50% of max position size
    end

    def too_correlated?(candidate, selected, constraints)
      # Simple correlation check: avoid too many stocks from same sector
      sector = get_sector(candidate)
      return false unless sector

      same_sector_count = selected.count { |c| c[:sector] == sector }
      same_sector_count >= constraints[:max_per_sector]
    end

    def determine_tier(candidate, position_index)
      # Tier 1: Top 3-5 positions (actionable now)
      return "tier_1" if position_index < 5

      # Tier 2: Next 5-10 (watchlist/waiting)
      return "tier_2" if position_index < 10

      # Tier 3: Rest (market strength, informational)
      "tier_3"
    end

    def select_longterm_candidates
      return [] if @longterm_candidates.empty?

      # For long-term, use screener score primarily (AI ranking optional)
      ranked = @longterm_candidates.map do |candidate|
        screener_score = candidate[:score] || 0
        ai_score = candidate[:ai_score] || 0
        # Long-term: 70% screener, 30% AI (if available)
        combined_score = ai_score.positive? ? (screener_score * 0.7) + (ai_score * 0.3) : screener_score

        candidate.merge(
          combined_score: combined_score.round(2),
          rank: nil,
        )
      end

      # Sort by combined score
      ranked.sort_by { |c| -c[:combined_score] }.first(@longterm_limit).each_with_index do |candidate, index|
        candidate[:rank] = index + 1
      end
    end

    def build_summary
      swing_selected = select_swing_candidates
      longterm_selected = select_longterm_candidates

      {
        swing_count: @swing_candidates.size,
        swing_selected: swing_selected.size,
        longterm_count: @longterm_candidates.size,
        longterm_selected: longterm_selected.size,
        tier_1_count: swing_selected.count { |c| c[:tier] == "tier_1" },
        tier_2_count: swing_selected.count { |c| c[:tier] == "tier_2" },
        tier_3_count: swing_selected.count { |c| c[:tier] == "tier_3" },
        timestamp: Time.current,
      }
    end

    def build_tiers
      swing_selected = select_swing_candidates

      {
        tier_1: swing_selected.select { |c| c[:tier] == "tier_1" },
        tier_2: swing_selected.select { |c| c[:tier] == "tier_2" },
        tier_3: swing_selected.select { |c| c[:tier] == "tier_3" },
      }
    end
  end
end

