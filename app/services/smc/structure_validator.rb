# frozen_string_literal: true

module Smc
  # SMC Structure Validator
  # Validates market structure using Smart Money Concepts
  class StructureValidator
    # Validate SMC structure for a candle series
    # @param candles [Array<Candle>] Array of candles
    # @param direction [Symbol] :long or :short (expected direction)
    # @param config [Hash] Validation configuration
    # @return [Hash] Validation result
    #   {
    #     valid: Boolean,
    #     score: Float (0-100),
    #     reasons: Array<String>,
    #     structure: Hash (BOS, CHOCH, order_blocks, fvgs, mitigation_blocks)
    #   }
    def self.validate(candles, direction: :long, config: {})
      return invalid_result("Insufficient candles") if candles.nil? || candles.size < 50

      structure = analyze_structure(candles, config)
      validation = check_structure_requirements(structure, direction, config)

      {
        valid: validation[:valid],
        score: validation[:score],
        reasons: validation[:reasons],
        structure: structure,
      }
    end

    def self.analyze_structure(candles, config)
      lookback = config[:lookback] || 20

      {
        bos: BOS.detect(candles, lookback: lookback),
        choch: CHOCH.detect(candles, lookback: lookback),
        order_blocks: OrderBlock.detect(candles, lookback: lookback * 2),
        fvgs: FairValueGap.detect(candles, lookback: lookback * 2),
        mitigation_blocks: MitigationBlock.detect(candles, lookback: lookback * 2),
      }
    end

    def self.check_structure_requirements(structure, direction, config)
      score = 0.0
      max_score = 0.0
      reasons = []
      _valid = false

      # BOS validation
      if config[:require_bos] != false
        max_score += 30
        if structure[:bos]
          if (direction == :long && structure[:bos][:type] == :bullish) ||
             (direction == :short && structure[:bos][:type] == :bearish)
            score += 30
            reasons << "BOS detected: #{structure[:bos][:type]}"
            _valid = true if config[:require_bos] == true
          else
            reasons << "BOS mismatch: expected #{direction}, got #{structure[:bos][:type]}"
          end
        else
          reasons << "No BOS detected"
        end
      end

      # CHOCH validation
      if config[:require_choch] != false
        max_score += 20
        if structure[:choch]
          if (direction == :long && structure[:choch][:type] == :bullish) ||
             (direction == :short && structure[:choch][:type] == :bearish)
            score += 20
            reasons << "CHOCH detected: #{structure[:choch][:type]}"
          else
            reasons << "CHOCH mismatch: expected #{direction}, got #{structure[:choch][:type]}"
          end
        end
      end

      # Order blocks validation
      if config[:require_order_blocks] != false
        max_score += 25
        relevant_blocks = structure[:order_blocks].select do |block|
          (direction == :long && block[:type] == :bullish) ||
            (direction == :short && block[:type] == :bearish)
        end

        if relevant_blocks.any?
          # Score based on block strength and recency
          block_score = relevant_blocks.sum { |b| b[:strength] * 10 }
          score += [block_score, 25].min
          reasons << "#{relevant_blocks.size} #{direction} order block(s) found"
        else
          reasons << "No #{direction} order blocks found"
        end
      end

      # Fair value gaps validation
      if config[:require_fvgs] != false
        max_score += 15
        relevant_fvgs = structure[:fvgs].select do |fvg|
          (direction == :long && fvg[:type] == :bullish && !fvg[:filled]) ||
            (direction == :short && fvg[:type] == :bearish && !fvg[:filled])
        end

        if relevant_fvgs.any?
          score += 15
          reasons << "#{relevant_fvgs.size} unfilled #{direction} FVG(s) found"
        end
      end

      # Mitigation blocks validation
      if config[:require_mitigation_blocks] != false
        max_score += 10
        block_type = direction == :long ? :support : :resistance
        relevant_blocks = structure[:mitigation_blocks].select do |block|
          block[:type] == block_type && block[:strength] >= 0.5
        end

        if relevant_blocks.any?
          score += 10
          reasons << "#{relevant_blocks.size} strong #{block_type} mitigation block(s) found"
        end
      end

      # Calculate final score (0-100)
      final_score = max_score.positive? ? (score / max_score * 100).round(2) : 0.0

      # Determine validity
      min_score = config[:min_score] || 50.0
      is_valid = final_score >= min_score

      {
        valid: is_valid,
        score: final_score,
        reasons: reasons,
      }
    end

    def self.invalid_result(reason)
      {
        valid: false,
        score: 0.0,
        reasons: [reason],
        structure: {},
      }
    end
  end
end
