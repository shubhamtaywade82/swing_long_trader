# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::ProcessApprovedJob, type: :job do
  let(:instrument) { create(:instrument) }
  let(:order) { create(:order, instrument: instrument, status: 'pending', approved_at: Time.current) }

  describe '#perform' do
    context 'when specific order_id is provided' do
      before do
        order
        allow(Dhan::Orders).to receive(:place_order).and_return(
          { success: true, order: order }
        )
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'processes only that order' do
        result = described_class.new.perform(order_id: order.id)

        expect(result[:success]).to be true
        expect(Dhan::Orders).to have_received(:place_order)
      end
    end

    context 'when no order_id provided' do
      before do
        order
        allow(Dhan::Orders).to receive(:place_order).and_return(
          { success: true, order: order }
        )
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'processes all approved orders' do
        result = described_class.new.perform

        expect(result[:processed]).to eq(1)
        expect(result[:success]).to eq(1)
      end
    end

    context 'when no approved orders exist' do
      before do
        create(:order, status: 'pending', approved_at: nil)
      end

      it 'returns success with zero processed' do
        result = described_class.new.perform

        expect(result[:success]).to be true
        expect(result[:processed]).to eq(0)
      end
    end

    context 'when order is not approved' do
      let(:order) { create(:order, status: 'pending', approved_at: nil) }

      before do
        order
      end

      it 'skips order' do
        result = described_class.new.perform(order_id: order.id)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Order not approved')
      end
    end

    context 'when order placement fails' do
      before do
        order
        allow(Dhan::Orders).to receive(:place_order).and_return(
          { success: false, error: 'Insufficient funds' }
        )
      end

      it 'updates order status to failed' do
        described_class.new.perform(order_id: order.id)

        order.reload
        expect(order.status).to eq('failed')
        expect(order.error_message).to eq('Insufficient funds')
      end
    end

    context 'when job fails' do
      before do
        allow(Order).to receive(:approved).and_raise(StandardError, 'Database error')
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

