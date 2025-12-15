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

    def self.call(swing_candidates: [], longterm_candidates: [], swing_limit: nil, longterm_limit: nil, portfolio: nil, screener_run_id: nil)
      new(
        swing_candidates: swing_candidates,
        longterm_candidates: longterm_candidates,
        swing_limit: swing_limit,
        longterm_limit: longterm_limit,
        portfolio: portfolio,
        screener_run_id: screener_run_id,
      ).call
    end

    def initialize(swing_candidates: [], longterm_candidates: [], swing_limit: nil, longterm_limit: nil, portfolio: nil, screener_run_id: nil)
      @swing_candidates = swing_candidates
      @longterm_candidates = longterm_candidates
      @swing_limit = swing_limit || DEFAULT_SWING_LIMIT
      @longterm_limit = longterm_limit || DEFAULT_LONGTERM_LIMIT
      @portfolio = portfolio || load_default_portfolio
      @screener_run_id = screener_run_id
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
      # Prefer paper portfolio for screening (safer, allows testing)
      # Initialize paper portfolio if it doesn't exist or has no capital
      paper_portfolio = CapitalAllocationPortfolio.paper.active.first

      if paper_portfolio
        # Ensure it has valid capital allocated
        if paper_portfolio.total_equity.zero? || paper_portfolio.available_swing_capital <= 0
          result = Portfolios::PaperPortfolioInitializer.call
          paper_portfolio = result[:portfolio] if result[:success]
        end
        return paper_portfolio if paper_portfolio&.available_swing_capital&.positive?
      else
        # Create paper portfolio if none exists
        result = Portfolios::PaperPortfolioInitializer.call
        return result[:portfolio] if result[:success]
      end

      # Fallback to any active portfolio (could be live)
      CapitalAllocationPortfolio.active.first || nil
    end

    def select_swing_candidates
      return [] if @swing_candidates.empty?

      # Get portfolio constraints
      constraints = get_portfolio_constraints

      # Rank candidates by combined score
      ranked = rank_candidates(@swing_candidates)

      # Preload all instruments and IndexConstituents to avoid N+1 queries
      preload_instruments_and_constituents(ranked)

      # Apply portfolio filters
      selected = []
      sector_counts = {}
      current_positions = get_current_positions

      ranked.each do |candidate|
        # Check max positions limit (global)
        break if selected.size >= constraints[:max_positions]

        # Check action budget (daily limit)
        if constraints[:remaining_trades_today] && constraints[:remaining_trades_today] <= 0
          Rails.logger.info("[Screeners::FinalSelector] Daily trade limit reached (#{constraints[:trades_taken_today]}/#{constraints[:max_trades_today]})")
          break
        end

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

        # Update remaining trades count
        if constraints[:remaining_trades_today]
          constraints[:remaining_trades_today] -= 1
        end
      end

      # Set ranks and persist final stage
      selected.each_with_index do |candidate, index|
        candidate[:rank] = index + 1

        # Mark as final in database
        if @screener_run_id && candidate[:instrument_id]
          ActiveRecord::Base.transaction do
            screener_result = ScreenerResult.find_by(
              screener_run_id: @screener_run_id,
              instrument_id: candidate[:instrument_id],
              screener_type: "swing",
            )
            screener_result&.update_columns(stage: "final")
          end
        end
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
      return default_constraints unless @portfolio

      # Handle CapitalAllocationPortfolio (paper or live)
      if @portfolio.is_a?(CapitalAllocationPortfolio)
        base_constraints = if @portfolio.swing_risk_config
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
                               total_equity: @portfolio.total_equity || 100_000,
                             }
                           end
      # Handle PaperPortfolio (legacy paper trading system)
      elsif @portfolio.is_a?(PaperPortfolio)
        base_constraints = {
          max_positions: @config[:max_positions] || DEFAULT_MAX_POSITIONS,
          max_capital_pct: @config[:max_capital_pct] || DEFAULT_MAX_CAPITAL_PCT,
          max_per_sector: @config[:max_per_sector] || DEFAULT_MAX_PER_SECTOR,
          total_equity: @portfolio.total_equity || @portfolio.capital || 100_000,
        }
      else
        base_constraints = default_constraints
      end

      # Apply action budget (max trades/risk/capital per day)
      action_budget = get_action_budget
      base_constraints.merge(action_budget)
    end

    def default_constraints
      {
        max_positions: DEFAULT_MAX_POSITIONS,
        max_capital_pct: DEFAULT_MAX_CAPITAL_PCT,
        max_per_sector: DEFAULT_MAX_PER_SECTOR,
        total_equity: 100_000,
      }
    end

    # Get action budget: max trades/risk/capital deployable today
    def get_action_budget
      today = Date.current
      budget = {
        max_trades_today: @config[:max_trades_per_day] || DEFAULT_MAX_POSITIONS,
        max_risk_today: @config[:max_risk_per_day] || nil, # % of equity
        max_capital_today: @config[:max_capital_per_day] || nil, # % of equity
      }

      # Check how many trades were taken today
      if @portfolio
        today_positions = if @portfolio.is_a?(CapitalAllocationPortfolio)
                            @portfolio.open_swing_positions
                                      .where("created_at >= ?", today.beginning_of_day)
                                      .count
                          elsif @portfolio.is_a?(PaperPortfolio)
                            @portfolio.open_positions
                                      .where("opened_at >= ?", today.beginning_of_day)
                                      .count
                          else
                            0
                          end
        budget[:trades_taken_today] = today_positions
        budget[:remaining_trades_today] = [budget[:max_trades_today] - today_positions, 0].max
      end

      budget
    end

    def get_current_positions
      return [] unless @portfolio

      # Handle both CapitalAllocationPortfolio and PaperPortfolio
      positions = if @portfolio.is_a?(CapitalAllocationPortfolio)
                     @portfolio.open_swing_positions.includes(:instrument)
                   elsif @portfolio.is_a?(PaperPortfolio)
                     @portfolio.open_positions.includes(:instrument)
                   else
                     []
                   end

      positions.map do |pos|
        {
          symbol: pos.instrument&.symbol_name || pos.symbol,
          sector: get_sector_for_instrument(pos.instrument),
        }
      end
    end

    def preload_instruments_and_constituents(candidates)
      # Collect all instrument IDs
      instrument_ids = candidates.filter_map { |c| c[:instrument_id] }.compact.uniq
      return if instrument_ids.empty?

      # Preload all instruments in one query
      @preloaded_instruments ||= {}
      instruments = Instrument.where(id: instrument_ids).index_by(&:id)
      @preloaded_instruments.merge!(instruments)

      # Preload IndexConstituents by symbol and ISIN
      instrument_symbols = instruments.values.map(&:symbol_name).map(&:upcase).compact.uniq
      instrument_isins = instruments.values.filter_map(&:isin).map(&:upcase).compact.uniq

      @preloaded_constituents_by_symbol ||= {}
      @preloaded_constituents_by_isin ||= {}

      if instrument_symbols.any?
        IndexConstituent.where(symbol: instrument_symbols).each do |constituent|
          @preloaded_constituents_by_symbol[constituent.symbol.upcase] = constituent
        end
      end

      if instrument_isins.any?
        IndexConstituent.where(isin_code: instrument_isins).each do |constituent|
          @preloaded_constituents_by_isin[constituent.isin_code.upcase] = constituent
        end
      end
    end

    def get_sector(candidate)
      return nil unless candidate[:instrument_id]

      # Use preloaded instrument to avoid N+1 query
      instrument = @preloaded_instruments&.[](candidate[:instrument_id])
      return nil unless instrument

      get_sector_for_instrument(instrument)
    end

    def get_sector_for_instrument(instrument)
      return nil unless instrument

      # Use preloaded IndexConstituents to avoid N+1 queries
      # Try to get sector from IndexConstituent by symbol
      constituent = @preloaded_constituents_by_symbol&.[](instrument.symbol_name.upcase)
      return constituent.industry if constituent&.industry.present?

      # Fallback: try ISIN match
      if instrument.isin.present?
        constituent = @preloaded_constituents_by_isin&.[](instrument.isin.upcase)
        return constituent.industry if constituent&.industry.present?
      end

      nil
    end

    def has_sufficient_capital?(candidate, constraints)
      return true unless @portfolio

      # Estimate position size (10-15% of equity)
      max_position_value = constraints[:total_equity] * (constraints[:max_capital_pct] / 100.0)

      # Get available capital based on portfolio type
      available = if @portfolio.respond_to?(:available_swing_capital)
                     @portfolio.available_swing_capital || @portfolio.swing_capital || 0
                   elsif @portfolio.respond_to?(:available_capital)
                     @portfolio.available_capital || 0
                   else
                     0
                   end

      # Require at least 50% of max position size to be available
      available >= max_position_value * 0.5
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

      # Preload all instruments and IndexConstituents to avoid N+1 queries
      preload_instruments_and_constituents(@longterm_candidates)

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

