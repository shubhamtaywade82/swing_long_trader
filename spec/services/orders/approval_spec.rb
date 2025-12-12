# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Approval do
  let(:order) { create(:order, status: 'pending', requires_approval: true) }
  let(:instrument) { create(:instrument) }

  before do
    allow(Orders::ProcessApprovedJob).to receive(:perform_later)
    allow(Telegram::Notifier).to receive(:send_error_alert)
  end

  describe '.approve' do
    it 'approves an order' do
      result = described_class.approve(order.id, approved_by: 'admin')

      expect(result[:success]).to be true
      order.reload
      expect(order.approved_at).to be_present
      expect(order.approved_by).to eq('admin')
    end

    it 'enqueues ProcessApprovedJob' do
      described_class.approve(order.id)

      expect(Orders::ProcessApprovedJob).to have_received(:perform_later).with(order_id: order.id)
    end

    it 'sends notification' do
      described_class.approve(order.id)

      expect(Telegram::Notifier).to have_received(:send_error_alert)
    end

    it 'returns error if order not found' do
      result = described_class.approve(999_999)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Order not found')
    end

    it 'returns error if order does not require approval' do
      order.update(requires_approval: false)
      result = described_class.approve(order.id)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Order does not require approval')
    end

    it 'returns error if order already processed' do
      order.update(approved_at: Time.current)
      result = described_class.approve(order.id)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Order already processed')
    end
  end

  describe '.reject' do
    it 'rejects an order' do
      result = described_class.reject(order.id, reason: 'Risk too high', rejected_by: 'admin')

      expect(result[:success]).to be true
      order.reload
      expect(order.rejected_at).to be_present
      expect(order.rejected_by).to eq('admin')
      expect(order.rejection_reason).to eq('Risk too high')
      expect(order.status).to eq('cancelled')
    end

    it 'sends notification' do
      described_class.reject(order.id, reason: 'Test')

      expect(Telegram::Notifier).to have_received(:send_error_alert)
    end
  end
end

