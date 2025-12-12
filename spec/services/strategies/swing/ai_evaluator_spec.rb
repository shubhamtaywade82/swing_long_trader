# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::Swing::AIEvaluator, type: :service do
  let(:signal) do
    {
      symbol: 'RELIANCE',
      direction: 'long',
      entry_price: 100.0,
      sl: 95.0,
      tp: 110.0,
      rr: 2.0,
      confidence: 75,
      holding_days_estimate: 10
    }
  end

  describe '.call' do
    it 'delegates to instance method' do
      allow_any_instance_of(described_class).to receive(:call).and_return({ success: true })

      described_class.call(signal)

      expect_any_instance_of(described_class).to have_received(:call)
    end
  end

  describe '#call' do
    context 'when AI ranking is enabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          enabled: true,
          model: 'gpt-4o-mini',
          temperature: 0.3
        )
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: '{"score": 85, "confidence": 80, "summary": "Good signal", "risk": "medium"}',
            cached: false
          }
        )
      end

      it 'calls OpenAI service' do
        result = described_class.new(signal: signal).call

        expect(result[:success]).to be true
        expect(Openai::Service).to have_received(:call)
      end

      it 'parses and returns AI evaluation' do
        result = described_class.new(signal: signal).call

        expect(result[:ai_score]).to eq(85)
        expect(result[:ai_confidence]).to eq(80)
        expect(result[:ai_summary]).to eq('Good signal')
        expect(result[:ai_risk]).to eq('medium')
      end

      it 'includes cached status' do
        result = described_class.new(signal: signal).call

        expect(result[:cached]).to be false
      end
    end

    context 'when AI ranking is disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: false)
      end

      it 'returns error' do
        result = described_class.new(signal: signal).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('AI ranking disabled')
      end
    end

    context 'when signal is invalid' do
      it 'returns error' do
        result = described_class.new(signal: nil).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid signal')
      end
    end

    context 'when OpenAI call fails' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: true)
        allow(Openai::Service).to receive(:call).and_return(
          { success: false, error: 'API error' }
        )
      end

      it 'returns error' do
        result = described_class.new(signal: signal).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('API error')
      end
    end

    context 'when response parsing fails' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: true)
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: 'Invalid JSON'
          }
        )
      end

      it 'returns error' do
        result = described_class.new(signal: signal).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Failed to parse response')
      end
    end

    context 'when response contains markdown code blocks' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: true)
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: '```json\n{"score": 90, "confidence": 85, "summary": "Excellent", "risk": "low"}\n```'
          }
        )
      end

      it 'extracts and parses JSON correctly' do
        result = described_class.new(signal: signal).call

        expect(result[:success]).to be true
        expect(result[:ai_score]).to eq(90)
      end
    end
  end
end

