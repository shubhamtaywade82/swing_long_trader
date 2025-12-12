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
end

