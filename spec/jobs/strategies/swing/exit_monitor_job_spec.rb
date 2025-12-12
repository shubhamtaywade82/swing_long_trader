# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::Swing::ExitMonitorJob, type: :job do
  let(:instrument) { create(:instrument) }
  let(:order) { create(:order, instrument: instrument, status: 'placed', transaction_type: 'BUY') }

  describe '#perform' do
    context 'when stop loss is triggered' do
      before do
        order
        allow(instrument).to receive(:ltp).and_return(95.0)
        order.update(metadata: { stop_loss: 96.0, entry_price: 100.0 }.to_json)
        allow(Dhan::Orders).to receive(:place_order).and_return(
          { success: true, order: create(:order, transaction_type: 'SELL') }
        )
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'places exit order' do
        result = described_class.new.perform

        expect(result[:exits_triggered].size).to eq(1)
        expect(Dhan::Orders).to have_received(:place_order)
      end
    end

    context 'when take profit is triggered' do
      before do
        order
        allow(instrument).to receive(:ltp).and_return(110.0)
        order.update(metadata: { take_profit: 108.0, entry_price: 100.0 }.to_json)
        allow(Dhan::Orders).to receive(:place_order).and_return(
          { success: true, order: create(:order, transaction_type: 'SELL') }
        )
      end

      it 'places exit order' do
        result = described_class.new.perform

        expect(result[:exits_triggered].size).to eq(1)
      end
    end

    context 'when no exit conditions met' do
      before do
        order
        allow(instrument).to receive(:ltp).and_return(102.0)
        order.update(metadata: { stop_loss: 95.0, take_profit: 110.0, entry_price: 100.0 }.to_json)
      end

      it 'does not place exit order' do
        result = described_class.new.perform

        expect(result[:exits_triggered]).to be_empty
      end
    end

    context 'when no active orders' do
      before do
        create(:order, status: 'executed')
      end

      it 'returns zero exits' do
        result = described_class.new.perform

        expect(result[:active_orders]).to eq(0)
        expect(result[:exits_triggered]).to be_empty
      end
    end

    context 'when job fails' do
      before do
        allow(Order).to receive(:where).and_raise(StandardError, 'Database error')
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'sends error alert and raises' do
        expect do
          described_class.new.perform
        end.to raise_error(StandardError, 'Database error')

        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end
    end
  end
end

