# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaperPosition, type: :model do
  let(:portfolio) { create(:paper_portfolio) }
  let(:instrument) { create(:instrument) }
  let(:position) do
    create(:paper_position,
      paper_portfolio: portfolio,
      instrument: instrument,
      direction: 'long',
      entry_price: 100.0,
      current_price: 105.0,
      quantity: 10,
      status: 'open')
  end

  describe 'validations' do
    it 'requires direction' do
      position = PaperPosition.new(
        paper_portfolio: portfolio,
        instrument: instrument,
        entry_price: 100,
        current_price: 105,
        quantity: 10,
        status: 'open'
      )
      expect(position).not_to be_valid
      expect(position.errors[:direction]).to include("can't be blank")
    end

    it 'requires direction to be long or short' do
      position = PaperPosition.new(
        paper_portfolio: portfolio,
        instrument: instrument,
        direction: 'invalid',
        entry_price: 100,
        current_price: 105,
        quantity: 10,
        status: 'open'
      )
      expect(position).not_to be_valid
      expect(position.errors[:direction]).to be_present
    end

    it 'requires entry_price, current_price, and quantity' do
      position = PaperPosition.new(
        paper_portfolio: portfolio,
        instrument: instrument,
        direction: 'long',
        status: 'open'
      )
      expect(position).not_to be_valid
      expect(position.errors[:entry_price]).to be_present
      expect(position.errors[:current_price]).to be_present
      expect(position.errors[:quantity]).to be_present
    end
  end

  describe 'scopes' do
    it 'filters by open status' do
      open_pos = create(:paper_position, paper_portfolio: portfolio, status: 'open')
      closed_pos = create(:paper_position, paper_portfolio: portfolio, status: 'closed')

      expect(PaperPosition.open).to include(open_pos)
      expect(PaperPosition.open).not_to include(closed_pos)
    end

    it 'filters by direction' do
      long_pos = create(:paper_position, paper_portfolio: portfolio, direction: 'long')
      short_pos = create(:paper_position, paper_portfolio: portfolio, direction: 'short')

      expect(PaperPosition.long).to include(long_pos)
      expect(PaperPosition.long).not_to include(short_pos)
      expect(PaperPosition.short).to include(short_pos)
      expect(PaperPosition.short).not_to include(long_pos)
    end
  end

  describe '#unrealized_pnl' do
    it 'calculates profit for long position' do
      position = create(:paper_position,
        direction: 'long',
        entry_price: 100,
        current_price: 105,
        quantity: 10)
      expect(position.unrealized_pnl).to eq(50) # (105 - 100) * 10
    end

    it 'calculates profit for short position' do
      position = create(:paper_position,
        direction: 'short',
        entry_price: 100,
        current_price: 95,
        quantity: 10)
      expect(position.unrealized_pnl).to eq(50) # (100 - 95) * 10
    end
  end

  describe '#realized_pnl' do
    it 'calculates realized P&L for closed long position' do
      position = create(:paper_position,
        direction: 'long',
        entry_price: 100,
        exit_price: 110,
        quantity: 10,
        status: 'closed')
      expect(position.realized_pnl).to eq(100) # (110 - 100) * 10
    end

    it 'returns 0 for open position' do
      expect(position.realized_pnl).to eq(0)
    end
  end

  describe '#check_sl_hit?' do
    it 'returns true when stop loss is hit for long position' do
      position = create(:paper_position,
        direction: 'long',
        entry_price: 100,
        current_price: 95,
        sl: 96)
      expect(position.check_sl_hit?).to be true
    end

    it 'returns false when stop loss is not hit' do
      position = create(:paper_position,
        direction: 'long',
        entry_price: 100,
        current_price: 98,
        sl: 96)
      expect(position.check_sl_hit?).to be false
    end
  end

  describe '#check_tp_hit?' do
    it 'returns true when take profit is hit for long position' do
      position = create(:paper_position,
        direction: 'long',
        entry_price: 100,
        current_price: 106,
        tp: 105)
      expect(position.check_tp_hit?).to be true
    end
  end

  describe '#update_current_price!' do
    it 'updates current price and recalculates P&L' do
      position.update_current_price!(110.0)
      expect(position.current_price).to eq(110.0)
      expect(position.pnl).to eq(100) # (110 - 100) * 10
    end
  end

  describe '#metadata_hash' do
    it 'returns parsed JSON metadata' do
      position.update(metadata: '{"key": "value"}')
      expect(position.metadata_hash).to eq({ 'key' => 'value' })
    end

    it 'returns empty hash for blank metadata' do
      expect(position.metadata_hash).to eq({})
    end

    it 'returns empty hash for invalid JSON' do
      position.update(metadata: 'invalid json')
      expect(position.metadata_hash).to eq({})
    end
  end

  describe 'status methods' do
    it 'checks open status' do
      position.status = 'open'
      expect(position.open?).to be true
      expect(position.closed?).to be false
    end

    it 'checks closed status' do
      position.status = 'closed'
      expect(position.open?).to be false
      expect(position.closed?).to be true
    end
  end

  describe 'direction methods' do
    it 'checks long direction' do
      position.direction = 'long'
      expect(position.long?).to be true
      expect(position.short?).to be false
    end

    it 'checks short direction' do
      position.direction = 'short'
      expect(position.long?).to be false
      expect(position.short?).to be true
    end
  end

  describe '#entry_value' do
    it 'calculates entry value' do
      expect(position.entry_value).to eq(1000.0) # 100 * 10
    end
  end

  describe '#current_value' do
    it 'calculates current value' do
      expect(position.current_value).to eq(1050.0) # 105 * 10
    end
  end

  describe '#unrealized_pnl_pct' do
    it 'calculates unrealized P&L percentage for long position' do
      position = create(:paper_position,
        direction: 'long',
        entry_price: 100,
        current_price: 110,
        quantity: 10)
      expect(position.unrealized_pnl_pct).to eq(10.0) # (110 - 100) / 100 * 100
    end

    it 'calculates unrealized P&L percentage for short position' do
      position = create(:paper_position,
        direction: 'short',
        entry_price: 100,
        current_price: 90,
        quantity: 10)
      expect(position.unrealized_pnl_pct).to eq(10.0) # (100 - 90) / 100 * 100
    end

    it 'handles very small entry_price' do
      position = create(:paper_position,
        direction: 'long',
        entry_price: 0.01,
        current_price: 0.02,
        quantity: 10)
      expect(position.unrealized_pnl_pct).to eq(100.0) # (0.02 - 0.01) / 0.01 * 100
    end
  end

  describe '#realized_pnl_pct' do
    it 'calculates realized P&L percentage for closed long position' do
      position = create(:paper_position,
        direction: 'long',
        entry_price: 100,
        exit_price: 110,
        quantity: 10,
        status: 'closed')
      expect(position.realized_pnl_pct).to eq(10.0) # (110 - 100) / 100 * 100
    end

    it 'calculates realized P&L percentage for closed short position' do
      position = create(:paper_position,
        direction: 'short',
        entry_price: 100,
        exit_price: 90,
        quantity: 10,
        status: 'closed')
      expect(position.realized_pnl_pct).to eq(10.0) # (100 - 90) / 100 * 100
    end

    it 'returns 0 for open position' do
      expect(position.realized_pnl_pct).to eq(0)
    end

    it 'returns 0 if exit_price is nil' do
      position.status = 'closed'
      position.exit_price = nil
      expect(position.realized_pnl_pct).to eq(0)
    end
  end

  describe '#update_unrealized_pnl!' do
    it 'updates P&L for open position' do
      position.current_price = 110.0
      position.update_unrealized_pnl!

      expect(position.pnl).to eq(100) # (110 - 100) * 10
      expect(position.pnl_pct).to eq(10.0) # (110 - 100) / 100 * 100
    end

    it 'does nothing for closed position' do
      position.status = 'closed'
      position.pnl = 50
      position.pnl_pct = 5.0
      position.current_price = 110.0

      position.update_unrealized_pnl!

      expect(position.pnl).to eq(50) # Should remain unchanged
      expect(position.pnl_pct).to eq(5.0)
    end
  end

  describe '#check_sl_hit?' do
    context 'for short positions' do
      it 'returns true when stop loss is hit' do
        position = create(:paper_position,
          direction: 'short',
          entry_price: 100,
          current_price: 106,
          sl: 105)
        expect(position.check_sl_hit?).to be true
      end

      it 'returns false when stop loss is not hit' do
        position = create(:paper_position,
          direction: 'short',
          entry_price: 100,
          current_price: 103,
          sl: 105)
        expect(position.check_sl_hit?).to be false
      end
    end

    it 'returns false if sl is nil' do
      position.sl = nil
      expect(position.check_sl_hit?).to be false
    end
  end

  describe '#check_tp_hit?' do
    context 'for short positions' do
      it 'returns true when take profit is hit' do
        position = create(:paper_position,
          direction: 'short',
          entry_price: 100,
          current_price: 89,
          tp: 90)
        expect(position.check_tp_hit?).to be true
      end

      it 'returns false when take profit is not hit' do
        position = create(:paper_position,
          direction: 'short',
          entry_price: 100,
          current_price: 92,
          tp: 90)
        expect(position.check_tp_hit?).to be false
      end
    end

    it 'returns false if tp is nil' do
      position.tp = nil
      expect(position.check_tp_hit?).to be false
    end
  end

  describe '#days_held' do
    it 'calculates days held from opened_at' do
      position.opened_at = 5.days.ago
      expect(position.days_held).to eq(5)
    end

    it 'returns 0 if opened_at is nil' do
      position.opened_at = nil
      expect(position.days_held).to eq(0)
    end
  end

  describe 'scopes' do
    it 'filters recent positions' do
      old_pos = create(:paper_position, paper_portfolio: portfolio, opened_at: 10.days.ago)
      new_pos = create(:paper_position, paper_portfolio: portfolio, opened_at: 1.day.ago)

      recent = PaperPosition.recent.limit(1)
      expect(recent).to include(new_pos)
      expect(recent).not_to include(old_pos)
    end
  end

  describe 'edge cases' do
    it 'handles unrealized_pnl_pct with zero entry_price' do
      position = create(:paper_position,
        direction: 'long',
        entry_price: 0,
        current_price: 10,
        quantity: 10)
      expect(position.unrealized_pnl_pct).to eq(0)
    end

    it 'handles unrealized_pnl for long position with loss' do
      position = create(:paper_position,
        direction: 'long',
        entry_price: 100,
        current_price: 95,
        quantity: 10)
      expect(position.unrealized_pnl).to eq(-50) # (95 - 100) * 10
    end

    it 'handles unrealized_pnl for short position with loss' do
      position = create(:paper_position,
        direction: 'short',
        entry_price: 100,
        current_price: 105,
        quantity: 10)
      expect(position.unrealized_pnl).to eq(-50) # (100 - 105) * 10
    end

    it 'handles unrealized_pnl_pct for long position with loss' do
      position = create(:paper_position,
        direction: 'long',
        entry_price: 100,
        current_price: 95,
        quantity: 10)
      expect(position.unrealized_pnl_pct).to eq(-5.0) # (95 - 100) / 100 * 100
    end

    it 'handles unrealized_pnl_pct for short position with loss' do
      position = create(:paper_position,
        direction: 'short',
        entry_price: 100,
        current_price: 105,
        quantity: 10)
      expect(position.unrealized_pnl_pct).to eq(-5.0) # (100 - 105) / 100 * 100
    end

    it 'handles realized_pnl for short position' do
      position = create(:paper_position,
        direction: 'short',
        entry_price: 100,
        exit_price: 90,
        quantity: 10,
        status: 'closed')
      expect(position.realized_pnl).to eq(100) # (100 - 90) * 10
    end

    it 'handles realized_pnl for short position with loss' do
      position = create(:paper_position,
        direction: 'short',
        entry_price: 100,
        exit_price: 110,
        quantity: 10,
        status: 'closed')
      expect(position.realized_pnl).to eq(-100) # (100 - 110) * 10
    end

    it 'handles realized_pnl_pct for short position with loss' do
      position = create(:paper_position,
        direction: 'short',
        entry_price: 100,
        exit_price: 110,
        quantity: 10,
        status: 'closed')
      expect(position.realized_pnl_pct).to eq(-10.0) # (100 - 110) / 100 * 100
    end

    it 'handles check_sl_hit? with exact sl price for long' do
      position = create(:paper_position,
        direction: 'long',
        entry_price: 100,
        current_price: 95,
        sl: 95)
      expect(position.check_sl_hit?).to be true
    end

    it 'handles check_sl_hit? with exact sl price for short' do
      position = create(:paper_position,
        direction: 'short',
        entry_price: 100,
        current_price: 105,
        sl: 105)
      expect(position.check_sl_hit?).to be true
    end

    it 'handles check_tp_hit? with exact tp price for long' do
      position = create(:paper_position,
        direction: 'long',
        entry_price: 100,
        current_price: 110,
        tp: 110)
      expect(position.check_tp_hit?).to be true
    end

    it 'handles check_tp_hit? with exact tp price for short' do
      position = create(:paper_position,
        direction: 'short',
        entry_price: 100,
        current_price: 90,
        tp: 90)
      expect(position.check_tp_hit?).to be true
    end

    it 'handles update_current_price! with string price' do
      position.update_current_price!('110.5')
      expect(position.current_price).to eq(110.5)
    end

    it 'handles days_held with very recent opened_at' do
      position.opened_at = 1.hour.ago
      expect(position.days_held).to eq(0) # Less than 1 day
    end

    it 'handles days_held with exactly 1 day ago' do
      position.opened_at = 1.day.ago
      expect(position.days_held).to eq(1)
    end

    it 'handles entry_value with zero quantity' do
      position.quantity = 0
      expect(position.entry_value).to eq(0)
    end

    it 'handles current_value with zero quantity' do
      position.quantity = 0
      expect(position.current_value).to eq(0)
    end

    it 'handles metadata_hash with empty string' do
      position.update(metadata: '')
      expect(position.metadata_hash).to eq({})
    end
  end
end

