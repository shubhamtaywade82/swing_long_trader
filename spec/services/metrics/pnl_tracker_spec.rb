# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Metrics::PnlTracker do
  let(:order) { create(:order, transaction_type: 'BUY', quantity: 10, price: 100.0) }

  before do
    allow(Setting).to receive(:fetch_f).and_return(0.0)
    allow(Setting).to receive(:put)
  end

  describe '.calculate_realized_pnl' do
    it 'calculates profit for buy order' do
      order.update(status: 'executed', average_price: 110.0, filled_quantity: 10)

      pnl = described_class.calculate_realized_pnl(order)

      expect(pnl).to eq(100.0) # (110 - 100) * 10
    end

    it 'calculates loss for buy order' do
      order.update(status: 'executed', average_price: 90.0, filled_quantity: 10)

      pnl = described_class.calculate_realized_pnl(order)

      expect(pnl).to eq(-100.0) # (90 - 100) * 10
    end

    it 'returns 0 for non-executed order' do
      pnl = described_class.calculate_realized_pnl(order)

      expect(pnl).to eq(0)
    end
  end

  describe '.calculate_unrealized_pnl' do
    it 'calculates unrealized profit for buy order' do
      order.update(status: 'placed')

      pnl = described_class.calculate_unrealized_pnl(order, 110.0)

      expect(pnl).to eq(100.0) # (110 - 100) * 10
    end

    it 'returns 0 for non-placed order' do
      pnl = described_class.calculate_unrealized_pnl(order, 110.0)

      expect(pnl).to eq(0)
    end
  end

  describe '#track_order_execution' do
    it 'tracks P&L for executed order' do
      order.update(status: 'executed', average_price: 110.0, filled_quantity: 10)

      result = described_class.track_order_execution(order)

      expect(result[:pnl]).to eq(100.0)
      expect(result[:pnl_pct]).to eq(10.0) # (100 / 1000) * 100
    end

    it 'does not track for non-executed order' do
      result = described_class.track_order_execution(order)

      expect(result).to be_nil
    end
  end

  describe '.get_daily_pnl' do
    it 'calculates total P&L for a date' do
      # Create orders with executed status and metadata containing P&L
      today = Date.today
      # Use date range to ensure we match the date regardless of time
      order1 = create(:order, created_at: today.beginning_of_day + 1.hour, status: 'executed')
      order1.update_column(:metadata, { 'pnl' => 100.0 }.to_json)

      order2 = create(:order, created_at: today.beginning_of_day + 2.hours, status: 'executed')
      order2.update_column(:metadata, { 'pnl' => 50.0 }.to_json)

      # Verify orders are found by the query (use date range instead of DATE() function)
      orders_for_today = Order.where(created_at: today.beginning_of_day..today.end_of_day).executed
      expect(orders_for_today.count).to eq(2), "Expected 2 orders, found #{orders_for_today.count}. Orders: #{Order.executed.pluck(:id, :created_at, :status)}"

      # Verify metadata is accessible
      order1.reload
      order2.reload
      expect(order1.metadata_hash['pnl']).to eq(100.0)
      expect(order2.metadata_hash['pnl']).to eq(50.0)

      pnl = described_class.get_daily_pnl(today)

      expect(pnl).to eq(150.0)
    end
  end
end

