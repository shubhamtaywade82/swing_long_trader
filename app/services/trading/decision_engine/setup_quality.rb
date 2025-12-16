# frozen_string_literal: true

module Trading
  module DecisionEngine
    # Filters weak setups based on trend and momentum
    # Reuses existing indicator values - NO recalculation
    class SetupQuality
      def self.call(trade_recommendation, config: {})
        new(trade_recommendation, config: config).call
      end

      def initialize(trade_recommendation, config: {})
        @recommendation = trade_recommendation
        @config = config
      end

      def call
        errors = []

        # Check trend still valid
        trend_check = check_trend_validity
        errors.concat(trend_check[:errors]) unless trend_check[:approved]

        # Check momentum not diverging
        momentum_check = check_momentum_alignment
        errors.concat(momentum_check[:errors]) unless momentum_check[:approved]

        # Check no immediate invalidation
        invalidation_check = check_invalidation_conditions
        errors.concat(invalidation_check[:errors]) unless invalidation_check[:approved]

        if errors.any?
          {
            approved: false,
            reason: "Setup quality check failed: #{errors.first}",
            errors: errors,
          }
        else
          {
            approved: true,
            reason: "Setup quality acceptable",
            errors: [],
          }
        end
      end

      private

      def check_trend_validity
        return { approved: true, errors: [] } unless @recommendation.facts

        facts = @recommendation.facts

        # For long trades, must be bullish
        if @recommendation.long?
          unless facts.bullish?
            return {
              approved: false,
              errors: ["Long trade requires bullish trend"],
            }
          end

          # Check trend flags are present
          unless facts.trend_flags.any?
            return {
              approved: false,
              errors: ["No trend confirmation flags present"],
            }
          end
        end

        # For short trades, must be bearish
        if @recommendation.short?
          unless facts.bearish?
            return {
              approved: false,
              errors: ["Short trade requires bearish trend"],
            }
          end
        end

        { approved: true, errors: [] }
      end

      def check_momentum_alignment
        return { approved: true, errors: [] } unless @recommendation.facts

        facts = @recommendation.facts

        # Check for momentum divergence (conflicting signals)
        bullish_momentum = facts.momentum_flags.include?(:rsi_bullish) ||
                          facts.momentum_flags.include?(:macd_bullish)
        bearish_momentum = facts.momentum_flags.include?(:rsi_bearish) ||
                          facts.momentum_flags.include?(:macd_bearish)

        # For long trades, should not have bearish momentum
        if @recommendation.long? && bearish_momentum && !bullish_momentum
          return {
            approved: false,
            errors: ["Momentum diverging - bearish signals for long trade"],
          }
        end

        # For short trades, should not have bullish momentum
        if @recommendation.short? && bullish_momentum && !bearish_momentum
          return {
            approved: false,
            errors: ["Momentum diverging - bullish signals for short trade"],
          }
        end

        { approved: true, errors: [] }
      end

      def check_invalidation_conditions
        return { approved: true, errors: [] } if @recommendation.invalidation_conditions.empty?

        # Check if setup_status indicates immediate invalidation
        if @recommendation.facts&.setup_status == "NOT_READY"
          return {
            approved: false,
            errors: ["Setup status is NOT_READY"],
          }
        end

        # Check if invalidation conditions are too strict (could be a warning, not blocking)
        # For now, just log - don't block unless explicitly marked as avoid

        { approved: true, errors: [] }
      end
    end
  end
end
