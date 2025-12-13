# frozen_string_literal: true

module LongTerm
  class Allocator < ApplicationService
    PER_STOCK_MAX = 10.0 # Percentage
    PER_SECTOR_MAX = 25.0 # Percentage

    def initialize(portfolio:, instruments:)
      @portfolio = portfolio
      @instruments = instruments
    end

    def call
      return failure("No instruments provided") if @instruments.empty?
      return failure("Insufficient long-term capital") if @portfolio.long_term_capital <= 0

      allocations = calculate_allocations
      return failure("Failed to calculate allocations") if allocations.empty?

      success(allocations: allocations)
    end

    def calculate_equal_weight_allocations
      count = @instruments.count
      return [] if count.zero?

      allocation_per_stock_pct = [PER_STOCK_MAX, (100.0 / count)].min
      total_capital = @portfolio.long_term_capital

      @instruments.map do |instrument|
        allocation_amount = (total_capital * allocation_per_stock_pct / 100.0).round(2)
        {
          instrument: instrument,
          allocation_pct: allocation_per_stock_pct,
          allocation_amount: allocation_amount,
        }
      end
    end

    def calculate_score_weighted_allocations(scores:)
      return [] if scores.empty? || scores.size != @instruments.size

      total_score = scores.sum.to_f
      return [] if total_score.zero?

      allocations = @instruments.zip(scores).map do |instrument, score|
        weight = score / total_score
        allocation_pct = [PER_STOCK_MAX, (weight * 100)].min
        allocation_amount = (@portfolio.long_term_capital * allocation_pct / 100.0).round(2)

        {
          instrument: instrument,
          allocation_pct: allocation_pct,
          allocation_amount: allocation_amount,
          score: score,
        }
      end

      # Ensure we don't exceed total capital
      total_allocated = allocations.sum { |a| a[:allocation_amount] }
      if total_allocated > @portfolio.long_term_capital
        scale_factor = @portfolio.long_term_capital / total_allocated
        allocations.each do |alloc|
          alloc[:allocation_amount] = (alloc[:allocation_amount] * scale_factor).round(2)
          alloc[:allocation_pct] = (alloc[:allocation_amount] / @portfolio.total_equity * 100).round(2)
        end
      end

      allocations
    end

    private

    def calculate_allocations
      # Default to equal weight
      calculate_equal_weight_allocations
    end

    def success(data)
      { success: true, **data }
    end

    def failure(message)
      { success: false, error: message }
    end
  end
end
