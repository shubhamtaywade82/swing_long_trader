# frozen_string_literal: true

module Trading
  module DecisionEngine
    # Enforces risk management rules
    # Pure function - uses portfolio if provided, otherwise uses defaults
    class RiskRules
      def self.call(trade_recommendation, portfolio: nil, system_context: nil, config: {})
        new(trade_recommendation, portfolio: portfolio, system_context: system_context, config: config).call
      end

      def initialize(trade_recommendation, portfolio: nil, system_context: nil, config: {})
        @recommendation = trade_recommendation
        @portfolio = portfolio
        @system_context = system_context
        @config = config
        @max_daily_risk_pct = config[:max_daily_risk_pct] || 2.0
        @max_volatility_pct = config[:max_volatility_pct] || 8.0
      end

      def call
        errors = []

        # Check per-trade risk percentage
        per_trade_risk_check = check_per_trade_risk
        errors.concat(per_trade_risk_check[:errors]) unless per_trade_risk_check[:approved]

        # Check daily risk limit
        daily_risk_check = check_daily_risk_limit
        errors.concat(daily_risk_check[:errors]) unless daily_risk_check[:approved]

        # Check system context constraints (drawdown, consecutive losses)
        context_check = check_system_context
        errors.concat(context_check[:errors]) unless context_check[:approved]

        # Check volatility cap (ATR %)
        volatility_check = check_volatility_cap
        errors.concat(volatility_check[:errors]) unless volatility_check[:approved]

        if errors.any?
          {
            approved: false,
            reason: "Risk rules violated: #{errors.first}",
            errors: errors,
          }
        else
          {
            approved: true,
            reason: "Risk rules passed",
            errors: [],
          }
        end
      end

      private

      def check_per_trade_risk
        return { approved: true, errors: [] } unless @portfolio

        # Get total capital
        total_capital = get_total_capital
        return { approved: true, errors: [] } if total_capital.zero?

        # Calculate risk amount as percentage of capital
        risk_pct = (@recommendation.risk_amount / total_capital * 100.0).round(2)

        # Per-trade risk should not exceed daily risk limit
        if risk_pct > @max_daily_risk_pct
          {
            approved: false,
            errors: ["Per-trade risk #{risk_pct}% exceeds daily limit #{@max_daily_risk_pct}%"],
          }
        else
          { approved: true, errors: [] }
        end
      end

      def check_daily_risk_limit
        return { approved: true, errors: [] } unless @portfolio

        # Get total capital
        total_capital = get_total_capital
        return { approved: true, errors: [] } if total_capital.zero?

        # Calculate today's risk (from positions opened today)
        today_risk = calculate_today_risk

        # Add this trade's risk
        total_daily_risk = today_risk + @recommendation.risk_amount
        daily_risk_pct = (total_daily_risk / total_capital * 100.0).round(2)

        if daily_risk_pct > @max_daily_risk_pct
          {
            approved: false,
            errors: ["Daily risk limit exceeded: #{daily_risk_pct}% > #{@max_daily_risk_pct}%"],
          }
        else
          { approved: true, errors: [] }
        end
      end

      def check_volatility_cap
        # Check ATR % if available in facts
        return { approved: true, errors: [] } unless @recommendation.facts

        indicators = @recommendation.facts.indicators_snapshot
        daily_indicators = if indicators.is_a?(Hash) && indicators.key?(:daily)
                            indicators[:daily]
                          else
                            indicators
                          end

        return { approved: true, errors: [] } unless daily_indicators.is_a?(Hash)

        atr = daily_indicators[:atr]
        latest_close = daily_indicators[:latest_close] || @recommendation.entry_price

        return { approved: true, errors: [] } unless atr && latest_close&.positive?

        # Calculate ATR as percentage of price
        atr_pct = (atr.to_f / latest_close * 100.0).round(2)

        if atr_pct > @max_volatility_pct
          {
            approved: false,
            errors: ["Volatility too high: ATR #{atr_pct}% > #{@max_volatility_pct}%"],
          }
        else
          { approved: true, errors: [] }
        end
      end

      def get_total_capital
        return 0 unless @portfolio

        if @portfolio.respond_to?(:total_equity)
          @portfolio.total_equity.to_f
        elsif @portfolio.respond_to?(:total_capital)
          @portfolio.total_capital.to_f
        else
          0.0
        end
      end

      def calculate_today_risk
        return 0.0 unless @portfolio

        today = Date.current

        # Get positions opened today
        open_positions = if @portfolio.respond_to?(:open_swing_positions)
                          @portfolio.open_swing_positions
                        elsif @portfolio.respond_to?(:open_positions)
                          @portfolio.open_positions
                        else
                          []
                        end

        # Sum risk_amount from positions opened today
        open_positions
          .where("created_at >= ?", today.beginning_of_day)
          .sum do |pos|
            # Calculate risk per position
            if pos.respond_to?(:risk_amount) && pos.risk_amount
              pos.risk_amount.to_f
            elsif pos.respond_to?(:entry_price) && pos.entry_price && pos.respond_to?(:stop_loss) && pos.stop_loss
              # Calculate from entry and SL
              risk_per_share = (pos.entry_price.to_f - pos.stop_loss.to_f).abs
              quantity = pos.respond_to?(:quantity) ? pos.quantity.to_i : 0
              risk_per_share * quantity
            else
              0.0
          end
        end
      end

      def check_system_context
        return { approved: true, errors: [] } unless @system_context

        errors = []

        # Check significant drawdown
        if @system_context.significant_drawdown?(threshold: 15.0)
          errors << "Significant drawdown detected: #{@system_context.drawdown.round(2)}%"
        end

        # Check consecutive losses (if configured)
        if @system_context.consecutive_losses >= 3
          errors << "Too many consecutive losses: #{@system_context.consecutive_losses}"
        end

        # Check losing day (optional - could be warning not blocker)
        # For now, just log - don't block

        if errors.any?
          {
            approved: false,
            errors: errors,
          }
        else
          { approved: true, errors: [] }
        end
      end
    end
  end
end
