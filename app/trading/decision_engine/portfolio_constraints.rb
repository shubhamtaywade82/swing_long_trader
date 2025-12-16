# frozen_string_literal: true

module Trading
  module DecisionEngine
    # Checks portfolio-level constraints
    # Pure function - uses portfolio if provided, otherwise passes
    class PortfolioConstraints
      def self.call(trade_recommendation, portfolio: nil, config: {})
        new(trade_recommendation, portfolio: portfolio, config: config).call
      end

      def initialize(trade_recommendation, portfolio: nil, config: {})
        @recommendation = trade_recommendation
        @portfolio = portfolio
        @config = config
        @max_positions_per_symbol = config[:max_positions_per_symbol] || 1
      end

      def call
        return { approved: true, reason: "No portfolio constraints" } unless @portfolio

        errors = []

        # Check max positions per symbol
        position_check = check_max_positions_per_symbol
        errors.concat(position_check[:errors]) unless position_check[:approved]

        # Check capital availability
        capital_check = check_capital_availability
        errors.concat(capital_check[:errors]) unless capital_check[:approved]

        if errors.any?
          {
            approved: false,
            reason: "Portfolio constraints violated: #{errors.first}",
            errors: errors,
          }
        else
          {
            approved: true,
            reason: "Portfolio constraints satisfied",
            errors: [],
          }
        end
      end

      private

      def check_max_positions_per_symbol
        # Get open positions for this instrument
        open_positions = get_open_positions_for_instrument

        if open_positions.count >= @max_positions_per_symbol
          {
            approved: false,
            errors: ["Max positions per symbol exceeded: #{open_positions.count}/#{@max_positions_per_symbol}"],
          }
        else
          { approved: true, errors: [] }
        end
      end

      def check_capital_availability
        # Calculate required capital
        required_capital = @recommendation.entry_price * @recommendation.quantity

        # Get available capital
        available_capital = get_available_capital

        if required_capital > available_capital
          {
            approved: false,
            errors: ["Insufficient capital: ₹#{required_capital.round(2)} required, ₹#{available_capital.round(2)} available"],
          }
        else
          { approved: true, errors: [] }
        end
      end

      def get_open_positions_for_instrument
        return [] unless @portfolio

        open_positions = if @portfolio.respond_to?(:open_swing_positions)
                          @portfolio.open_swing_positions
                        elsif @portfolio.respond_to?(:open_positions)
                          @portfolio.open_positions
                        else
                          []
                        end

        open_positions.where(instrument_id: @recommendation.instrument_id)
      end

      def get_available_capital
        return 0.0 unless @portfolio

        # Try swing capital first (for swing trades)
        if @recommendation.timeframe == "swing"
          if @portfolio.respond_to?(:available_swing_capital)
            return @portfolio.available_swing_capital.to_f
          end
        end

        # Fallback to general available capital
        if @portfolio.respond_to?(:available_capital)
          @portfolio.available_capital.to_f
        elsif @portfolio.respond_to?(:available_cash)
          @portfolio.available_cash.to_f
        else
          0.0
        end
      end
    end
  end
end
