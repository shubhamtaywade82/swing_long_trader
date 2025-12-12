# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Order, type: :model do
  let(:instrument) { create(:instrument, symbol_name: 'RELIANCE', security_id: '11536', exchange: 'NSE', segment: 'E') }
  let(:order) do
    create(:order,
      instrument: instrument,
      symbol: 'RELIANCE',
      security_id: '11536',
      product_type: 'EQUITY',
      order_type: 'MARKET',
      transaction_type: 'BUY',
      quantity: 100,
      status: 'pending')
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(order).to be_valid
    end

    it 'requires client_order_id' do
      order.client_order_id = nil
      expect(order).not_to be_valid
      expect(order.errors[:client_order_id]).to include("can't be blank")
    end

    it 'requires unique client_order_id' do
      duplicate_id = "B-11536-#{SecureRandom.hex(6)}"
      create(:order, client_order_id: duplicate_id, instrument: instrument)
      order.client_order_id = duplicate_id
      expect(order).not_to be_valid
      expect(order.errors[:client_order_id]).to include('has already been taken')
    end

    it 'requires transaction_type to be BUY or SELL' do
      order.transaction_type = 'INVALID'
      expect(order).not_to be_valid
      expect(order.errors[:transaction_type]).to include('is not included in the list')
    end

    it 'requires order_type to be valid' do
      order.order_type = 'INVALID'
      expect(order).not_to be_valid
      expect(order.errors[:order_type]).to include('is not included in the list')
    end

    it 'requires quantity to be positive' do
      order.quantity = 0
      expect(order).not_to be_valid
      expect(order.errors[:quantity]).to include('must be greater than 0')
    end
  end

  describe 'scopes' do
    before do
      create(:order, status: 'pending', instrument: instrument)
      create(:order, status: 'placed', instrument: instrument)
      create(:order, status: 'executed', instrument: instrument)
      create(:order, status: 'rejected', instrument: instrument)
      create(:order, status: 'cancelled', instrument: instrument)
      create(:order, status: 'failed', instrument: instrument)
      create(:order, status: 'pending', dry_run: true, instrument: instrument)
    end

    it 'filters by status' do
      expect(Order.pending.count).to eq(2)
      expect(Order.placed.count).to eq(1)
      expect(Order.executed.count).to eq(1)
      expect(Order.rejected.count).to eq(1)
      expect(Order.cancelled.count).to eq(1)
      expect(Order.failed.count).to eq(1)
    end

    it 'filters active orders' do
      expect(Order.active.count).to eq(3) # 2 pending + 1 placed
    end

    it 'filters dry-run orders' do
      expect(Order.dry_run.count).to eq(1)
      expect(Order.real.count).to eq(6)
    end

    it 'filters recent orders' do
      # Create orders with explicit timestamps to ensure ordering
      old_order = create(:order, instrument: instrument, created_at: 10.days.ago)
      new_order = create(:order, instrument: instrument, created_at: 1.day.ago)

      recent = Order.recent.to_a
      # Verify scope returns orders ordered by created_at desc
      expect(recent).to include(new_order)
      expect(recent).to include(old_order)
      # Verify ordering: most recent first
      recent_timestamps = recent.map(&:created_at)
      expect(recent_timestamps).to eq(recent_timestamps.sort.reverse)
    end
  end

  describe 'helper methods' do
    it 'returns metadata as hash' do
      order.update(metadata: { test: 'value' }.to_json)
      expect(order.metadata_hash).to eq({ 'test' => 'value' })
    end

    it 'returns empty hash for nil metadata' do
      order.update(metadata: nil)
      expect(order.metadata_hash).to eq({})
    end

    it 'returns dhan_response as hash' do
      order.update(dhan_response: { orderId: '123' }.to_json)
      expect(order.dhan_response_hash).to eq({ 'orderId' => '123' })
    end

    it 'checks status methods' do
      order.status = 'pending'
      expect(order.pending?).to be true
      expect(order.active?).to be true

      order.status = 'placed'
      expect(order.placed?).to be true
      expect(order.active?).to be true

      order.status = 'executed'
      expect(order.executed?).to be true
      expect(order.active?).to be false
    end

    it 'checks transaction type' do
      order.transaction_type = 'BUY'
      expect(order.buy?).to be true
      expect(order.sell?).to be false

      order.transaction_type = 'SELL'
      expect(order.buy?).to be false
      expect(order.sell?).to be true
    end

    it 'calculates total value' do
      order.price = 100.0
      order.quantity = 10
      expect(order.total_value).to eq(1000.0)
    end

    it 'calculates filled value' do
      order.average_price = 105.0
      order.filled_quantity = 5
      expect(order.filled_value).to eq(525.0)
    end

    it 'calculates total value with nil price' do
      order.price = nil
      order.quantity = 10
      expect(order.total_value).to eq(0)
    end

    it 'calculates filled value with nil average_price' do
      order.average_price = nil
      order.filled_quantity = 5
      expect(order.filled_value).to eq(0)
    end

    it 'checks cancelled status' do
      order.status = 'cancelled'
      expect(order.cancelled?).to be true
      expect(order.active?).to be false
    end

    it 'checks failed status' do
      order.status = 'failed'
      expect(order.failed?).to be true
      expect(order.active?).to be false
    end

    it 'checks requires_approval?' do
      order.requires_approval = true
      order.approved_at = nil
      order.rejected_at = nil
      expect(order.requires_approval?).to be true
    end

    it 'returns false for requires_approval? if already approved' do
      order.requires_approval = true
      order.approved_at = Time.current
      order.rejected_at = nil
      expect(order.requires_approval?).to be false
    end

    it 'returns false for requires_approval? if already rejected' do
      order.requires_approval = true
      order.approved_at = nil
      order.rejected_at = Time.current
      expect(order.requires_approval?).to be false
    end

    it 'checks approved status' do
      order.approved_at = Time.current
      expect(order.approved?).to be true
    end

    it 'checks rejected status' do
      order.rejected_at = Time.current
      expect(order.rejected?).to be true
    end

    it 'checks approval_pending status' do
      order.requires_approval = true
      order.approved_at = nil
      order.rejected_at = nil
      expect(order.approval_pending?).to be true
    end

    it 'returns false for approval_pending? if not requires_approval' do
      order.requires_approval = false
      expect(order.approval_pending?).to be false
    end
  end

  describe 'approval scopes' do
    before do
      create(:order, requires_approval: true, approved_at: nil, rejected_at: nil, instrument: instrument)
      create(:order, requires_approval: true, approved_at: Time.current, rejected_at: nil, instrument: instrument)
      create(:order, requires_approval: true, approved_at: nil, rejected_at: Time.current, instrument: instrument)
      create(:order, requires_approval: false, instrument: instrument)
    end

    it 'filters orders requiring approval' do
      expect(Order.requires_approval.count).to eq(1)
    end

    it 'filters approved orders' do
      expect(Order.approved.count).to eq(1)
    end

    it 'filters rejected orders' do
      expect(Order.rejected_for_approval.count).to eq(1)
    end

    it 'filters pending approval orders' do
      expect(Order.pending_approval.count).to eq(1)
    end
  end

  describe '#dhan_response_hash' do
    it 'returns empty hash for nil dhan_response' do
      order.dhan_response = nil
      expect(order.dhan_response_hash).to eq({})
    end

    it 'returns empty hash for invalid JSON' do
      order.dhan_response = 'invalid json'
      expect(order.dhan_response_hash).to eq({})
    end
  end
end

