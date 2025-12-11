# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Order, type: :model do
  let(:instrument) { create(:instrument, symbol_name: 'RELIANCE', security_id: '11536', exchange: 'NSE', segment: 'E') }
  let(:order) do
    create(:order,
      instrument: instrument,
      client_order_id: 'B-11536-123456',
      symbol: 'RELIANCE',
      exchange_segment: instrument.exchange_segment,
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
      create(:order, client_order_id: 'B-11536-123456', instrument: instrument)
      order.client_order_id = 'B-11536-123456'
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
  end
end

