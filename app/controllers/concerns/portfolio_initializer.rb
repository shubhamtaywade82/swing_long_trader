# frozen_string_literal: true

module PortfolioInitializer
  extend ActiveSupport::Concern

  private

  def ensure_paper_portfolio_initialized
    return @portfolio if @portfolio&.total_equity&.positive?

    initializer_result = Portfolios::PaperPortfolioInitializer.call
    if initializer_result[:success]
      @portfolio = initializer_result[:portfolio]
    else
      Rails.logger.error("[#{self.class.name}] Failed to initialize paper portfolio: #{initializer_result[:error]}")
      @portfolio = nil
    end
    @portfolio
  end
end
