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

  describe '.calculate_realized_pnl' do
    it 'calculates profit for sell order' do
      sell_order = create(:order, transaction_type: 'SELL', quantity: 10, price: 100.0)
      sell_order.update(status: 'executed', average_price: 90.0, filled_quantity: 10)

      pnl = described_class.calculate_realized_pnl(sell_order)

      expect(pnl).to eq(100.0) # (100 - 90) * 10
    end

    it 'calculates loss for sell order' do
      sell_order = create(:order, transaction_type: 'SELL', quantity: 10, price: 100.0)
      sell_order.update(status: 'executed', average_price: 110.0, filled_quantity: 10)

      pnl = described_class.calculate_realized_pnl(sell_order)

      expect(pnl).to eq(-100.0) # (100 - 110) * 10
    end

    it 'handles nil price' do
      order.update(price: nil, status: 'executed', average_price: 110.0, filled_quantity: 10)

      pnl = described_class.calculate_realized_pnl(order)

      expect(pnl).to eq(1100.0) # (110 - 0) * 10
    end

    it 'handles partial fills' do
      order.update(status: 'executed', average_price: 110.0, filled_quantity: 5)

      pnl = described_class.calculate_realized_pnl(order)

      expect(pnl).to eq(50.0) # (110 - 100) * 5
    end
  end

  describe '.calculate_unrealized_pnl' do
    it 'calculates unrealized loss for buy order' do
      order.update(status: 'placed')

      pnl = described_class.calculate_unrealized_pnl(order, 90.0)

      expect(pnl).to eq(-100.0) # (90 - 100) * 10
    end

    it 'calculates unrealized profit for sell order' do
      sell_order = create(:order, transaction_type: 'SELL', quantity: 10, price: 100.0, status: 'placed')

      pnl = described_class.calculate_unrealized_pnl(sell_order, 90.0)

      expect(pnl).to eq(100.0) # (100 - 90) * 10
    end

    it 'calculates unrealized loss for sell order' do
      sell_order = create(:order, transaction_type: 'SELL', quantity: 10, price: 100.0, status: 'placed')

      pnl = described_class.calculate_unrealized_pnl(sell_order, 110.0)

      expect(pnl).to eq(-100.0) # (100 - 110) * 10
    end

    it 'returns 0 for nil current_price' do
      order.update(status: 'placed')

      pnl = described_class.calculate_unrealized_pnl(order, nil)

      expect(pnl).to eq(0)
    end

    it 'handles nil price' do
      order.update(price: nil, status: 'placed')

      pnl = described_class.calculate_unrealized_pnl(order, 110.0)

      expect(pnl).to eq(1100.0) # (110 - 0) * 10
    end
  end

  describe '#track_order_execution' do
    it 'updates order metadata with P&L' do
      order.update(status: 'executed', average_price: 110.0, filled_quantity: 10)

      described_class.track_order_execution(order)

      order.reload
      metadata = order.metadata_hash
      expect(metadata['pnl']).to eq(100.0)
      expect(metadata['pnl_pct']).to eq(10.0)
      expect(metadata['executed_at']).to be_present
    end

    it 'tracks daily P&L' do
      order.update(status: 'executed', average_price: 110.0, filled_quantity: 10)
      allow(Setting).to receive(:fetch_f).with('pnl.daily.2025-12-12', 0.0).and_return(50.0)

      described_class.track_order_execution(order)

      expect(Setting).to have_received(:put).with('pnl.daily.2025-12-12', 150.0)
    end

    it 'handles zero entry value for P&L percentage' do
      order.update(price: 0, status: 'executed', average_price: 110.0, filled_quantity: 10)

      result = described_class.track_order_execution(order)

      expect(result[:pnl_pct]).to eq(0)
    end

    it 'logs P&L tracking' do
      order.update(status: 'executed', average_price: 110.0, filled_quantity: 10)
      allow(Rails.logger).to receive(:info)

      described_class.track_order_execution(order)

      expect(Rails.logger).to have_received(:info).with(/Tracked P&L/)
    end
  end

  describe '.get_weekly_pnl' do
    it 'calculates total P&L for a week' do
      week_start = Date.today.beginning_of_week
      order1 = create(:order, created_at: week_start + 1.day, status: 'executed')
      order1.update_column(:metadata, { 'pnl' => 100.0 }.to_json)
      order2 = create(:order, created_at: week_start + 3.days, status: 'executed')
      order2.update_column(:metadata, { 'pnl' => 50.0 }.to_json)

      pnl = described_class.get_weekly_pnl(week_start)

      expect(pnl).to eq(150.0)
    end
  end

  describe '.get_monthly_pnl' do
    it 'calculates total P&L for a month' do
      month_start = Date.today.beginning_of_month
      order1 = create(:order, created_at: month_start + 5.days, status: 'executed')
      order1.update_column(:metadata, { 'pnl' => 200.0 }.to_json)
      order2 = create(:order, created_at: month_start + 10.days, status: 'executed')
      order2.update_column(:metadata, { 'pnl' => 100.0 }.to_json)

      pnl = described_class.get_monthly_pnl(month_start)

      expect(pnl).to eq(300.0)
    end
  end

  describe '.get_total_pnl' do
    it 'calculates total P&L for all executed orders' do
      order1 = create(:order, status: 'executed')
      order1.update_column(:metadata, { 'pnl' => 150.0 }.to_json)
      order2 = create(:order, status: 'executed')
      order2.update_column(:metadata, { 'pnl' => 75.0 }.to_json)
      create(:order, status: 'pending') # Should not be included

      pnl = described_class.get_total_pnl

      expect(pnl).to eq(225.0)
    end

    it 'calculates P&L from order if not in metadata' do
      order.update(status: 'executed', average_price: 110.0, filled_quantity: 10)

      pnl = described_class.get_total_pnl

      expect(pnl).to eq(100.0)
    end
  end

  describe '#calculate_pnl_percentage' do
    it 'calculates percentage correctly' do
      order.update(price: 100.0, quantity: 10)
      tracker = described_class.new

      pct = tracker.send(:calculate_pnl_percentage, order, 50.0)

      expect(pct).to eq(5.0) # (50 / 1000) * 100
    end

    it 'returns 0 for zero entry value' do
      order.update(price: 0, quantity: 10)
      tracker = described_class.new

      pct = tracker.send(:calculate_pnl_percentage, order, 50.0)

      expect(pct).to eq(0)
    end
  end
end

