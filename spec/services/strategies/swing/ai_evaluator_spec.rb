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

    context 'with edge cases' do
      it 'handles missing fields in JSON response' do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: true)
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: '{"score": 85}'
          }
        )

        result = described_class.new(signal: signal).call

        expect(result[:success]).to be true
        expect(result[:ai_score]).to eq(85)
        expect(result[:ai_confidence]).to eq(0) # Default value
        expect(result[:ai_summary]).to eq('') # Default value
        expect(result[:ai_risk]).to eq('medium') # Default value
      end

      it 'handles nil content from OpenAI' do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: true)
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: nil
          }
        )

        result = described_class.new(signal: signal).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Failed to parse response')
      end

      it 'handles empty content from OpenAI' do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: true)
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: ''
          }
        )

        result = described_class.new(signal: signal).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Failed to parse response')
      end

      it 'handles JSON with string numbers' do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: true)
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: '{"score": "85", "confidence": "80", "summary": "Good", "risk": "LOW"}'
          }
        )

        result = described_class.new(signal: signal).call

        expect(result[:success]).to be true
        expect(result[:ai_score]).to eq(85.0)
        expect(result[:ai_confidence]).to eq(80.0)
        expect(result[:ai_risk]).to eq('low') # Should be downcased
      end

      it 'handles markdown with extra whitespace' do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: true)
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: '```json\n{"score": 90, "confidence": 85}\n```\n'
          }
        )

        result = described_class.new(signal: signal).call

        expect(result[:success]).to be true
        expect(result[:ai_score]).to eq(90)
      end

      it 'handles JSON parse errors gracefully' do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: true)
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: 'Not valid JSON {invalid}'
          }
        )
        allow(Rails.logger).to receive(:error)
        allow(Rails.logger).to receive(:debug)

        result = described_class.new(signal: signal).call

        expect(result[:success]).to be false
        expect(Rails.logger).to have_received(:error)
      end

      it 'handles standard errors during parsing' do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: true)
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: '{"score": 85}'
          }
        )
        allow(JSON).to receive(:parse).and_raise(StandardError, 'Unexpected error')
        allow(Rails.logger).to receive(:error)

        result = described_class.new(signal: signal).call

        expect(result[:success]).to be false
        expect(Rails.logger).to have_received(:error)
      end

      it 'uses custom model from config' do
        allow(AlgoConfig).to receive(:fetch).and_return(
          enabled: true,
          model: 'gpt-4',
          temperature: 0.5
        )
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: '{"score": 85, "confidence": 80, "summary": "Good", "risk": "medium"}'
          }
        )

        described_class.new(signal: signal).call

        expect(Openai::Service).to have_received(:call).with(
          hash_including(model: 'gpt-4', temperature: 0.5)
        )
      end

      it 'uses default model when not specified' do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: true)
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: '{"score": 85, "confidence": 80, "summary": "Good", "risk": "medium"}'
          }
        )

        described_class.new(signal: signal).call

        expect(Openai::Service).to have_received(:call).with(
          hash_including(model: 'gpt-4o-mini', temperature: 0.3)
        )
      end

      it 'handles signal with missing optional fields' do
        minimal_signal = {
          symbol: 'RELIANCE',
          direction: 'long',
          entry_price: 100.0
        }

        allow(AlgoConfig).to receive(:fetch).and_return(enabled: true)
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: '{"score": 85, "confidence": 80, "summary": "Good", "risk": "medium"}'
          }
        )

        result = described_class.new(signal: minimal_signal).call

        expect(result[:success]).to be true
        # Should still build prompt with available fields
        expect(Openai::Service).to have_received(:call)
      end
    end

    describe 'private methods' do
      let(:evaluator) { described_class.new(signal: signal) }

      describe '#build_prompt' do
        it 'builds prompt with all signal fields' do
          prompt = evaluator.send(:build_prompt)

          expect(prompt).to include('RELIANCE')
          expect(prompt).to include('long')
          expect(prompt).to include('100.0')
          expect(prompt).to include('95.0')
          expect(prompt).to include('110.0')
          expect(prompt).to include('2.0')
          expect(prompt).to include('75')
          expect(prompt).to include('10')
        end

        it 'handles signal with nil values' do
          signal_with_nils = signal.merge(rr: nil, holding_days_estimate: nil)
          evaluator = described_class.new(signal: signal_with_nils)

          prompt = evaluator.send(:build_prompt)

          expect(prompt).to include('RELIANCE')
          # Should handle nil values gracefully
        end
      end

      describe '#parse_response' do
        it 'parses valid JSON' do
          content = '{"score": 85, "confidence": 80, "summary": "Good", "risk": "medium"}'

          parsed = evaluator.send(:parse_response, content)

          expect(parsed).to have_key(:score)
          expect(parsed).to have_key(:confidence)
          expect(parsed).to have_key(:summary)
          expect(parsed).to have_key(:risk)
        end

        it 'handles nil content' do
          parsed = evaluator.send(:parse_response, nil)

          expect(parsed).to be_nil
        end

        it 'handles empty content' do
          parsed = evaluator.send(:parse_response, '')

          expect(parsed).to be_nil
        end

        it 'handles JSON with markdown code blocks' do
          content = '```json\n{"score": 90}\n```'

          parsed = evaluator.send(:parse_response, content)

          expect(parsed).to have_key(:score)
          expect(parsed[:score]).to eq(90)
        end

        it 'handles JSON parse errors' do
          content = 'Invalid JSON'
          allow(Rails.logger).to receive(:error)
          allow(Rails.logger).to receive(:debug)

          parsed = evaluator.send(:parse_response, content)

          expect(parsed).to be_nil
          expect(Rails.logger).to have_received(:error)
        end

        it 'downcases risk value' do
          content = '{"score": 85, "confidence": 80, "summary": "Good", "risk": "HIGH"}'

          parsed = evaluator.send(:parse_response, content)

          expect(parsed[:risk]).to eq('high')
        end

        it 'handles missing risk field' do
          content = '{"score": 85, "confidence": 80, "summary": "Good"}'

          parsed = evaluator.send(:parse_response, content)

          expect(parsed[:risk]).to eq('medium') # Default
        end
      end
    end
  end
end

