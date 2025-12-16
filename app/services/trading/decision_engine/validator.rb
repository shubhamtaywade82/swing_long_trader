# frozen_string_literal: true

module Trading
  module DecisionEngine
    # Validates TradeRecommendation structure and basic requirements
    # Pure function - no side effects, no database, no external calls
    class Validator
      def self.call(trade_recommendation, config: {})
        new(trade_recommendation, config: config).call
      end

      def initialize(trade_recommendation, config: {})
        @recommendation = trade_recommendation
        @config = config
        @min_rr = config[:min_risk_reward] || 2.0
        @min_confidence = config[:min_confidence] || 60.0
      end

      def call
        errors = []

        # Check required fields
        errors << "Missing entry_price" unless @recommendation.entry_price&.positive?
        errors << "Missing stop_loss" unless @recommendation.stop_loss&.positive?
        errors << "Missing quantity" unless @recommendation.quantity&.positive?
        errors << "Missing symbol" if @recommendation.symbol.blank?
        errors << "Missing instrument_id" unless @recommendation.instrument_id&.positive?

        # Check numeric sanity
        if @recommendation.entry_price&.positive? && @recommendation.stop_loss&.positive?
          # Entry and SL should be reasonable (not zero, not negative)
          errors << "Invalid entry_price" if @recommendation.entry_price <= 0
          errors << "Invalid stop_loss" if @recommendation.stop_loss <= 0

          # Stop loss should be below entry for long trades
          if @recommendation.long? && @recommendation.stop_loss >= @recommendation.entry_price
            errors << "Stop loss must be below entry price for long trades"
          end

          # Stop loss should be above entry for short trades
          if @recommendation.short? && @recommendation.stop_loss <= @recommendation.entry_price
            errors << "Stop loss must be above entry price for short trades"
          end
        end

        # Check risk-reward ratio
        if @recommendation.risk_reward < @min_rr
          errors << "Risk-reward ratio too low: #{@recommendation.risk_reward.round(2)} < #{@min_rr}"
        end

        # Check confidence score
        if @recommendation.confidence_score < @min_confidence
          errors << "Confidence score too low: #{@recommendation.confidence_score.round(1)} < #{@min_confidence}"
        end

        # Check bias is allowed
        unless %i[long short].include?(@recommendation.bias)
          errors << "Invalid bias: #{@recommendation.bias} (must be :long or :short)"
        end

        # Check avoid flag
        if @recommendation.avoid?
          errors << "Trade marked as avoid"
        end

        # Check target prices exist
        if @recommendation.target_prices.empty?
          errors << "No target prices specified"
        end

        if errors.any?
          {
            approved: false,
            reason: "Validation failed: #{errors.first}",
            errors: errors,
          }
        else
          {
            approved: true,
            reason: "Valid structure",
            errors: [],
          }
        end
      end
    end
  end
end
