# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BacktestPosition, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      position = build(:backtest_position)
      expect(position).to be_valid
    end

    it 'requires entry_date' do
      position = build(:backtest_position, entry_date: nil)
      expect(position).not_to be_valid
      expect(position.errors[:entry_date]).to include("can't be blank")
    end

    it 'requires direction' do
      position = build(:backtest_position, direction: nil)
      expect(position).not_to be_valid
      expect(position.errors[:direction]).to include("can't be blank")
    end

    it 'requires entry_price' do
      position = build(:backtest_position, entry_price: nil)
      expect(position).not_to be_valid
      expect(position.errors[:entry_price]).to include("can't be blank")
    end

    it 'requires quantity' do
      position = build(:backtest_position, quantity: nil)
      expect(position).not_to be_valid
      expect(position.errors[:quantity]).to include("can't be blank")
    end

    it 'validates direction inclusion' do
      position = build(:backtest_position, direction: 'invalid')
      expect(position).not_to be_valid
      expect(position.errors[:direction]).to include('is not included in the list')
    end
  end

  describe 'associations' do
    it 'belongs to backtest_run' do
      run = create(:backtest_run)
      position = create(:backtest_position, backtest_run: run)
      expect(position.backtest_run).to eq(run)
    end

    it 'belongs to instrument' do
      instrument = create(:instrument)
      position = create(:backtest_position, instrument: instrument)
      expect(position.instrument).to eq(instrument)
    end
  end

  describe 'scopes' do
    it 'long scope returns long positions' do
      long_pos = create(:backtest_position, direction: 'long')
      short_pos = create(:backtest_position, direction: 'short')

      long_positions = BacktestPosition.long
      expect(long_positions).to include(long_pos)
      expect(long_positions).not_to include(short_pos)
    end

    it 'short scope returns short positions' do
      long_pos = create(:backtest_position, direction: 'long')
      short_pos = create(:backtest_position, direction: 'short')

      short_positions = BacktestPosition.short
      expect(short_positions).to include(short_pos)
      expect(short_positions).not_to include(long_pos)
    end

    it 'closed scope returns closed positions' do
      closed = create(:backtest_position, exit_date: 1.day.ago)
      open_pos = create(:backtest_position, exit_date: nil)

      closed_positions = BacktestPosition.closed
      expect(closed_positions).to include(closed)
      expect(closed_positions).not_to include(open_pos)
    end

    it 'open scope returns open positions' do
      closed = create(:backtest_position, exit_date: 1.day.ago)
      open_pos = create(:backtest_position, exit_date: nil)

      open_positions = BacktestPosition.open
      expect(open_positions).to include(open_pos)
      expect(open_positions).not_to include(closed)
    end
  end

  describe 'status methods' do
    it 'closed? returns true when exit_date present' do
      position = create(:backtest_position, exit_date: 1.day.ago)
      expect(position.closed?).to be true
    end

    it 'closed? returns false when exit_date nil' do
      position = create(:backtest_position, exit_date: nil)
      expect(position.closed?).to be false
    end

    it 'open? returns true when exit_date nil' do
      position = create(:backtest_position, exit_date: nil)
      expect(position.open?).to be true
    end

    it 'open? returns false when exit_date present' do
      position = create(:backtest_position, exit_date: 1.day.ago)
      expect(position.open?).to be false
    end
  end

  describe '#calculate_pnl' do
    it 'returns 0 for open positions' do
      position = create(:backtest_position, exit_date: nil)
      expect(position.calculate_pnl).to eq(0)
    end

    it 'calculates profit for long position' do
      position = create(:backtest_position, direction: 'long', entry_price: 100.0, exit_price: 110.0, quantity: 100)
      expected_pnl = (110.0 - 100.0) * 100
      expect(position.calculate_pnl).to eq(expected_pnl)
    end

    it 'calculates profit for short position' do
      position = create(:backtest_position, direction: 'short', entry_price: 100.0, exit_price: 90.0, quantity: 100)
      expected_pnl = (100.0 - 90.0) * 100
      expect(position.calculate_pnl).to eq(expected_pnl)
    end
  end

  describe '#calculate_pnl_pct' do
    it 'returns 0 for open positions' do
      position = create(:backtest_position, exit_date: nil)
      expect(position.calculate_pnl_pct).to eq(0)
    end

    it 'calculates percentage for long position' do
      position = create(:backtest_position, direction: 'long', entry_price: 100.0, exit_price: 110.0)
      expected_pct = ((110.0 - 100.0) / 100.0 * 100).round(4)
      expect(position.calculate_pnl_pct).to eq(expected_pct)
    end

    it 'calculates percentage for short position' do
      position = create(:backtest_position, direction: 'short', entry_price: 100.0, exit_price: 90.0)
      expected_pct = ((100.0 - 90.0) / 100.0 * 100).round(4)
      expect(position.calculate_pnl_pct).to eq(expected_pct)
    end
  end

  describe 'edge cases' do
    it 'calculates loss for long position' do
      position = create(:backtest_position,
        direction: 'long',
        entry_price: 100.0,
        exit_price: 90.0,
        quantity: 100)
      expected_pnl = (90.0 - 100.0) * 100
      expect(position.calculate_pnl).to eq(expected_pnl)
    end

    it 'calculates loss for short position' do
      position = create(:backtest_position,
        direction: 'short',
        entry_price: 100.0,
        exit_price: 110.0,
        quantity: 100)
      expected_pnl = (100.0 - 110.0) * 100
      expect(position.calculate_pnl).to eq(expected_pnl)
    end

    it 'calculates P&L percentage for long position with loss' do
      position = create(:backtest_position,
        direction: 'long',
        entry_price: 100.0,
        exit_price: 90.0)
      expected_pct = ((90.0 - 100.0) / 100.0 * 100).round(4)
      expect(position.calculate_pnl_pct).to eq(expected_pct)
    end

    it 'calculates P&L percentage for short position with loss' do
      position = create(:backtest_position,
        direction: 'short',
        entry_price: 100.0,
        exit_price: 110.0)
      expected_pct = ((100.0 - 110.0) / 100.0 * 100).round(4)
      expect(position.calculate_pnl_pct).to eq(expected_pct)
    end

    it 'handles zero quantity' do
      position = create(:backtest_position,
        direction: 'long',
        entry_price: 100.0,
        exit_price: 110.0,
        quantity: 0)
      expect(position.calculate_pnl).to eq(0)
    end

    it 'handles zero entry_price in P&L percentage' do
      position = create(:backtest_position,
        direction: 'long',
        entry_price: 0,
        exit_price: 110.0,
        quantity: 100)
      # Should handle division by zero gracefully
      pct = position.calculate_pnl_pct
      expect(pct).to be_a(Numeric)
    end

    it 'handles calculate_pnl with invalid direction' do
      position = create(:backtest_position,
        direction: 'long',
        entry_price: 100.0,
        exit_price: 110.0,
        quantity: 100)
      # Mock invalid direction
      allow(position).to receive(:direction).and_return('invalid')
      expect(position.calculate_pnl).to eq(0)
    end

    it 'handles calculate_pnl_pct with invalid direction' do
      position = create(:backtest_position,
        direction: 'long',
        entry_price: 100.0,
        exit_price: 110.0,
        quantity: 100)
      # Mock invalid direction
      allow(position).to receive(:direction).and_return('invalid')
      expect(position.calculate_pnl_pct).to eq(0)
    end

    it 'handles closed? with empty string exit_date' do
      position = create(:backtest_position, exit_date: nil)
      position.exit_date = ''
      # Should handle empty string as nil
      expect(position.closed?).to be false
    end

    it 'handles open? with empty string exit_date' do
      position = create(:backtest_position, exit_date: nil)
      position.exit_date = ''
      # Should handle empty string as nil
      expect(position.open?).to be true
    end
  end
end

