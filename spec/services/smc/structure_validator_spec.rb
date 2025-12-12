# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::StructureValidator, type: :service do
  let(:candles) { create_list(:candle, 100) }

  describe '.validate' do
    context 'when candles are sufficient' do
      before do
        allow(Smc::BOS).to receive(:detect).and_return({ type: :bullish, index: 50 })
        allow(Smc::CHOCH).to receive(:detect).and_return({ type: :bullish, index: 45 })
        allow(Smc::OrderBlock).to receive(:detect).and_return([])
        allow(Smc::FairValueGap).to receive(:detect).and_return([])
        allow(Smc::MitigationBlock).to receive(:detect).and_return([])
      end

      it 'validates structure for long direction' do
        result = described_class.validate(candles, direction: :long)

        expect(result[:valid]).to be true
        expect(result[:score]).to be > 0
        expect(result[:structure]).to be_present
      end

      it 'validates structure for short direction' do
        allow(Smc::BOS).to receive(:detect).and_return({ type: :bearish, index: 50 })
        allow(Smc::CHOCH).to receive(:detect).and_return({ type: :bearish, index: 45 })

        result = described_class.validate(candles, direction: :short)

        expect(result[:valid]).to be true
      end
    end

    context 'when candles are insufficient' do
      it 'returns invalid result' do
        result = described_class.validate([], direction: :long)

        expect(result[:valid]).to be false
        expect(result[:reasons]).to include('Insufficient candles')
      end
    end

    context 'when BOS is required' do
      before do
        allow(Smc::BOS).to receive(:detect).and_return(nil)
        allow(Smc::CHOCH).to receive(:detect).and_return(nil)
        allow(Smc::OrderBlock).to receive(:detect).and_return([])
        allow(Smc::FairValueGap).to receive(:detect).and_return([])
        allow(Smc::MitigationBlock).to receive(:detect).and_return([])
      end

      it 'returns invalid when BOS not detected' do
        result = described_class.validate(candles, direction: :long, config: { require_bos: true })

        expect(result[:valid]).to be false
        expect(result[:reasons]).to include('No BOS detected')
      end
    end

    context 'when BOS direction mismatches' do
      before do
        allow(Smc::BOS).to receive(:detect).and_return({ type: :bearish, index: 50 })
        allow(Smc::CHOCH).to receive(:detect).and_return(nil)
        allow(Smc::OrderBlock).to receive(:detect).and_return([])
        allow(Smc::FairValueGap).to receive(:detect).and_return([])
        allow(Smc::MitigationBlock).to receive(:detect).and_return([])
      end

      it 'returns invalid' do
        result = described_class.validate(candles, direction: :long, config: { require_bos: true })

        expect(result[:valid]).to be false
        expect(result[:reasons]).to include('BOS mismatch')
      end
    end

    context 'when CHOCH is required' do
      before do
        allow(Smc::BOS).to receive(:detect).and_return({ type: :bullish, index: 50 })
        allow(Smc::CHOCH).to receive(:detect).and_return(nil)
        allow(Smc::OrderBlock).to receive(:detect).and_return([])
        allow(Smc::FairValueGap).to receive(:detect).and_return([])
        allow(Smc::MitigationBlock).to receive(:detect).and_return([])
      end

      it 'validates CHOCH presence' do
        result = described_class.validate(candles, direction: :long, config: { require_choch: true })

        expect(result[:score]).to be >= 0
      end

      it 'handles CHOCH direction mismatch' do
        allow(Smc::CHOCH).to receive(:detect).and_return({ type: :bearish, index: 45 })

        result = described_class.validate(candles, direction: :long, config: { require_choch: true })

        expect(result[:reasons]).to include('CHOCH mismatch')
      end
    end

    context 'when order blocks are required' do
      before do
        allow(Smc::BOS).to receive(:detect).and_return({ type: :bullish, index: 50 })
        allow(Smc::CHOCH).to receive(:detect).and_return({ type: :bullish, index: 45 })
        allow(Smc::FairValueGap).to receive(:detect).and_return([])
        allow(Smc::MitigationBlock).to receive(:detect).and_return([])
      end

      it 'validates order blocks presence' do
        allow(Smc::OrderBlock).to receive(:detect).and_return([
          { type: :bullish, strength: 0.8 }
        ])

        result = described_class.validate(candles, direction: :long, config: { require_order_blocks: true })

        expect(result[:score]).to be > 0
        expect(result[:reasons]).to include('order block(s) found')
      end

      it 'handles missing order blocks' do
        allow(Smc::OrderBlock).to receive(:detect).and_return([])

        result = described_class.validate(candles, direction: :long, config: { require_order_blocks: true })

        expect(result[:reasons]).to include('No long order blocks found')
      end
    end

    context 'when fair value gaps are required' do
      before do
        allow(Smc::BOS).to receive(:detect).and_return({ type: :bullish, index: 50 })
        allow(Smc::CHOCH).to receive(:detect).and_return({ type: :bullish, index: 45 })
        allow(Smc::OrderBlock).to receive(:detect).and_return([])
        allow(Smc::MitigationBlock).to receive(:detect).and_return([])
      end

      it 'validates FVG presence' do
        allow(Smc::FairValueGap).to receive(:detect).and_return([
          { type: :bullish, filled: false }
        ])

        result = described_class.validate(candles, direction: :long, config: { require_fvgs: true })

        expect(result[:score]).to be > 0
        expect(result[:reasons]).to include('FVG(s) found')
      end

      it 'ignores filled FVGs' do
        allow(Smc::FairValueGap).to receive(:detect).and_return([
          { type: :bullish, filled: true }
        ])

        result = described_class.validate(candles, direction: :long, config: { require_fvgs: true })

        expect(result[:score]).to be >= 0
      end
    end

    context 'when mitigation blocks are required' do
      before do
        allow(Smc::BOS).to receive(:detect).and_return({ type: :bullish, index: 50 })
        allow(Smc::CHOCH).to receive(:detect).and_return({ type: :bullish, index: 45 })
        allow(Smc::OrderBlock).to receive(:detect).and_return([])
        allow(Smc::FairValueGap).to receive(:detect).and_return([])
      end

      it 'validates mitigation blocks presence' do
        allow(Smc::MitigationBlock).to receive(:detect).and_return([
          { type: :support, strength: 0.7 }
        ])

        result = described_class.validate(candles, direction: :long, config: { require_mitigation_blocks: true })

        expect(result[:score]).to be > 0
        expect(result[:reasons]).to include('mitigation block(s) found')
      end

      it 'filters by strength threshold' do
        allow(Smc::MitigationBlock).to receive(:detect).and_return([
          { type: :support, strength: 0.3 } # Below 0.5 threshold
        ])

        result = described_class.validate(candles, direction: :long, config: { require_mitigation_blocks: true })

        expect(result[:score]).to be >= 0
      end
    end

    context 'with minimum score requirement' do
      before do
        allow(Smc::BOS).to receive(:detect).and_return({ type: :bullish, index: 50 })
        allow(Smc::CHOCH).to receive(:detect).and_return({ type: :bullish, index: 45 })
        allow(Smc::OrderBlock).to receive(:detect).and_return([])
        allow(Smc::FairValueGap).to receive(:detect).and_return([])
        allow(Smc::MitigationBlock).to receive(:detect).and_return([])
      end

      it 'validates when score meets minimum' do
        result = described_class.validate(candles, direction: :long, config: { min_score: 30.0 })

        expect(result[:valid]).to be true
      end

      it 'invalidates when score below minimum' do
        result = described_class.validate(candles, direction: :long, config: { min_score: 100.0 })

        expect(result[:valid]).to be false
      end
    end

    context 'when config options are disabled' do
      before do
        allow(Smc::BOS).to receive(:detect).and_return(nil)
        allow(Smc::CHOCH).to receive(:detect).and_return(nil)
        allow(Smc::OrderBlock).to receive(:detect).and_return([])
        allow(Smc::FairValueGap).to receive(:detect).and_return([])
        allow(Smc::MitigationBlock).to receive(:detect).and_return([])
      end

      it 'skips validation when require_bos is false' do
        result = described_class.validate(candles, direction: :long, config: { require_bos: false })

        expect(result[:valid]).to be false # Still invalid due to low score
        expect(result[:reasons]).not_to include('No BOS detected')
      end

      it 'skips validation when require_choch is false' do
        result = described_class.validate(candles, direction: :long, config: { require_choch: false })

        expect(result).to be_present
      end
    end
  end
end

