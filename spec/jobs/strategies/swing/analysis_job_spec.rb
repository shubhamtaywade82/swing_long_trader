# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::Swing::AnalysisJob, type: :job do
  let(:instrument) { create(:instrument) }
  let(:candidate_ids) { [instrument.id] }

  describe '#perform' do
    context 'when analysis succeeds' do
      let(:signal) do
        {
          instrument_id: instrument.id,
          symbol: instrument.symbol_name,
          direction: 'long',
          entry_price: 100.0
        }
      end

      before do
        allow(Strategies::Swing::Evaluator).to receive(:call).and_return(
          { success: true, signal: signal }
        )
        allow(AlgoConfig).to receive(:fetch).and_return(true)
        allow(Telegram::Notifier).to receive(:send_signal_alert)
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'evaluates candidates and generates signals' do
        result = described_class.new.perform(candidate_ids)

        expect(result.size).to eq(1)
        expect(result.first).to eq(signal)
        expect(Strategies::Swing::Evaluator).to have_received(:call)
      end

      it 'sends signal alerts when enabled' do
        described_class.new.perform(candidate_ids)

        expect(Telegram::Notifier).to have_received(:send_signal_alert).with(signal)
      end

      it 'skips failed evaluations' do
        allow(Strategies::Swing::Evaluator).to receive(:call).and_return(
          { success: false, error: 'Evaluation failed' }
        )

        result = described_class.new.perform(candidate_ids)

        expect(result).to be_empty
      end
    end

    context 'when notifications are disabled' do
      before do
        allow(Strategies::Swing::Evaluator).to receive(:call).and_return(
          { success: true, signal: { instrument_id: instrument.id } }
        )
        allow(AlgoConfig).to receive(:fetch).and_return(false)
        allow(Telegram::Notifier).to receive(:send_signal_alert)
      end

      it 'does not send signal alerts' do
        described_class.new.perform(candidate_ids)

        expect(Telegram::Notifier).not_to have_received(:send_signal_alert)
      end
    end

    context 'when analysis fails' do
      before do
        allow(Strategies::Swing::Evaluator).to receive(:call).and_raise(StandardError, 'Analysis error')
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'sends error alert and raises' do
        expect do
          described_class.new.perform(candidate_ids)
        end.to raise_error(StandardError, 'Analysis error')

        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end
    end
  end
end

