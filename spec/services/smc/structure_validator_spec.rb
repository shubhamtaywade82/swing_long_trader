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
  end
end

