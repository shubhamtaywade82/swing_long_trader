# frozen_string_literal: true

module Portfolios
  # Creates daily portfolio snapshots from positions
  # Portfolio includes positions that continue from previous day
  class DailySnapshot < ApplicationService
    def self.create_for_date(date:, portfolio_type: "all")
      new(date: date, portfolio_type: portfolio_type).create
    end

    def initialize(date:, portfolio_type: "all")
      @date = date.is_a?(Date) ? date : Date.parse(date.to_s)
      @portfolio_type = portfolio_type
    end

    def create
      results = {}

      if @portfolio_type == "all" || @portfolio_type == "live"
        results[:live] = create_live_portfolio
      end

      if @portfolio_type == "all" || @portfolio_type == "paper"
        results[:paper] = create_paper_portfolio
      end

      results
    end

    private

    def create_live_portfolio
      # Check if portfolio already exists for this date
      existing = Portfolio.find_by(portfolio_type: "live", date: @date)
      return { success: false, error: "Portfolio already exists for #{@date}" } if existing

      # Create portfolio from positions
      portfolio = Portfolio.create_from_positions(
        date: @date,
        portfolio_type: "live",
        name: "live_portfolio",
      )

      {
        success: true,
        portfolio: portfolio,
        message: "Live portfolio snapshot created for #{@date}",
      }
    rescue StandardError => e
      Rails.logger.error("[Portfolios::DailySnapshot] Failed to create live portfolio: #{e.message}")
      { success: false, error: e.message }
    end

    def create_paper_portfolio
      # Check if portfolio already exists for this date
      existing = Portfolio.find_by(portfolio_type: "paper", date: @date)
      return { success: false, error: "Portfolio already exists for #{@date}" } if existing

      # Create portfolio from positions
      portfolio = Portfolio.create_from_positions(
        date: @date,
        portfolio_type: "paper",
        name: "paper_portfolio",
      )

      {
        success: true,
        portfolio: portfolio,
        message: "Paper portfolio snapshot created for #{@date}",
      }
    rescue StandardError => e
      Rails.logger.error("[Portfolios::DailySnapshot] Failed to create paper portfolio: #{e.message}")
      { success: false, error: e.message }
    end
  end
end
