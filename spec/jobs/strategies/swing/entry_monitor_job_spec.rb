# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::Swing::EntryMonitorJob, type: :job do
  let(:instrument) { create(:instrument) }
  let(:signal) do
    {
      instrument_id: instrument.id,
      symbol: instrument.symbol_name,
      direction: 'long',
      entry_price: 100.0,
      qty: 10
    }
  end

  describe '#perform' do
    context 'when candidate_ids are provided' do
      before do
        allow(Strategies::Swing::Evaluator).to receive(:call).and_return(
          { success: true, signal: signal }
        )
        allow(Strategies::Swing::Executor).to receive(:call).and_return(
          { success: true, order: create(:order) }
        )
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'evaluates candidates and places orders' do
        result = described_class.new.perform(candidate_ids: [instrument.id])

        expect(result[:signals].size).to eq(1)
        expect(result[:orders_placed].size).to eq(1)
        expect(Strategies::Swing::Evaluator).to have_received(:call)
        expect(Strategies::Swing::Executor).to have_received(:call)
      end
    end

    context 'when no candidate_ids provided' do
      before do
        allow_any_instance_of(described_class).to receive(:get_top_candidates).and_return(
          [{ instrument_id: instrument.id }]
        )
        allow(Strategies::Swing::Evaluator).to receive(:call).and_return(
          { success: true, signal: signal }
        )
        allow(Strategies::Swing::Executor).to receive(:call).and_return(
          { success: true, order: create(:order) }
        )
      end

      it 'uses top candidates' do
        result = described_class.new.perform

        expect(result[:signals].size).to eq(1)
      end
    end

    context 'when already in position' do
      let!(:existing_order) { create(:order, instrument: instrument, status: 'placed') }

      before do
        allow(Strategies::Swing::Evaluator).to receive(:call).and_return(
          { success: true, signal: signal }
        )
      end

      it 'skips execution' do
        result = described_class.new.perform(candidate_ids: [instrument.id])

        expect(result[:orders_placed]).to be_empty
        expect(Strategies::Swing::Executor).not_to have_received(:call)
      end
    end

    context 'when evaluation fails' do
      before do
        allow(Strategies::Swing::Evaluator).to receive(:call).and_return(
          { success: false, error: 'Evaluation failed' }
        )
      end

      it 'skips failed candidates' do
        result = described_class.new.perform(candidate_ids: [instrument.id])

        expect(result[:signals]).to be_empty
        expect(result[:orders_placed]).to be_empty
      end
    end

    context 'when execution fails' do
      before do
        allow(Strategies::Swing::Evaluator).to receive(:call).and_return(
          { success: true, signal: signal }
        )
        allow(Strategies::Swing::Executor).to receive(:call).and_return(
          { success: false, error: 'Execution failed' }
        )
      end

      it 'logs warning but continues' do
        allow(Rails.logger).to receive(:warn)

        result = described_class.new.perform(candidate_ids: [instrument.id])

        expect(result[:orders_placed]).to be_empty
        expect(Rails.logger).to have_received(:warn)
      end
    end

    context 'when job fails completely' do
      before do
        allow(Strategies::Swing::Evaluator).to receive(:call).and_raise(StandardError, 'Critical error')
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'sends error alert and raises' do
        expect do
          described_class.new.perform(candidate_ids: [instrument.id])
        end.to raise_error(StandardError, 'Critical error')

        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end
    end
  end
end

