# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaperTrading::Simulator, type: :service do
  let(:portfolio) { create(:paper_portfolio, capital: 100_000) }
  let(:instrument) { create(:instrument) }

  describe '.check_exits' do
    context 'when portfolio is provided' do
      it 'uses provided portfolio' do
        allow(PaperTrading::Portfolio).to receive(:find_or_create_default)
        allow_any_instance_of(described_class).to receive(:check_exits).and_return({ checked: 0, exited: 0 })

        described_class.check_exits(portfolio: portfolio)

        expect(PaperTrading::Portfolio).not_to have_received(:find_or_create_default)
      end
    end

    context 'when portfolio is not provided' do
      let(:default_portfolio) { create(:paper_portfolio, name: 'default') }

      before do
        allow(PaperTrading::Portfolio).to receive(:find_or_create_default).and_return(default_portfolio)
        allow_any_instance_of(described_class).to receive(:check_exits).and_return({ checked: 0, exited: 0 })
      end

      it 'uses default portfolio' do
        described_class.check_exits

        expect(PaperTrading::Portfolio).to have_received(:find_or_create_default)
      end
    end
  end

  describe '#check_exits' do
    context 'when there are no open positions' do
      it 'returns zero checked and exited' do
        result = described_class.new(portfolio: portfolio).check_exits

        expect(result[:checked]).to eq(0)
        expect(result[:exited]).to eq(0)
      end
    end

    context 'when position hits stop loss' do
      let(:position) do
        create(:paper_position,
          paper_portfolio: portfolio,
          instrument: instrument,
          entry_price: 100.0,
          current_price: 100.0,
          sl: 95.0,
          status: 'open')
      end

      before do
        position
        create(:candle_series_record,
          instrument: instrument,
          timeframe: '1D',
          close: 94.0,
          timestamp: Time.current)
        allow(position).to receive(:check_sl_hit?).and_return(true)
        allow(position).to receive(:update_current_price!)
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it 'exits the position' do
        expect do
          described_class.new(portfolio: portfolio).check_exits
        end.to change { position.reload.status }.from('open').to('closed')
      end

      it 'updates position with exit details' do
        described_class.new(portfolio: portfolio).check_exits

        position.reload
        expect(position.exit_reason).to eq('sl_hit')
        expect(position.exit_price).to eq(95.0)
        expect(position.closed_at).to be_present
      end

      it 'releases reserved capital' do
        initial_reserved = portfolio.reserved_capital
        entry_value = position.entry_price * position.quantity

        described_class.new(portfolio: portfolio).check_exits

        portfolio.reload
        expect(portfolio.reserved_capital).to eq(initial_reserved - entry_value)
      end
    end

    context 'when position hits take profit' do
      let(:position) do
        create(:paper_position,
          paper_portfolio: portfolio,
          instrument: instrument,
          entry_price: 100.0,
          current_price: 100.0,
          tp: 110.0,
          status: 'open')
      end

      before do
        position
        allow(position).to receive(:check_sl_hit?).and_return(false)
        allow(position).to receive(:check_tp_hit?).and_return(true)
        allow(position).to receive(:update_current_price!)
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it 'exits the position' do
        expect do
          described_class.new(portfolio: portfolio).check_exits
        end.to change { position.reload.status }.from('open').to('closed')
      end

      it 'updates position with exit details' do
        described_class.new(portfolio: portfolio).check_exits

        position.reload
        expect(position.exit_reason).to eq('tp_hit')
        expect(position.exit_price).to eq(110.0)
      end

      it 'calculates profit correctly for long position' do
        described_class.new(portfolio: portfolio).check_exits

        position.reload
        expected_pnl = (110.0 - 100.0) * position.quantity
        expect(position.pnl).to eq(expected_pnl)
        expect(position.pnl_pct).to be > 0
      end
    end

    context 'when position exceeds max holding days' do
      let(:position) do
        create(:paper_position,
          paper_portfolio: portfolio,
          instrument: instrument,
          entry_price: 100.0,
          current_price: 100.0,
          opened_at: 21.days.ago,
          status: 'open')
      end

      before do
        position
        allow(position).to receive(:check_sl_hit?).and_return(false)
        allow(position).to receive(:check_tp_hit?).and_return(false)
        allow(position).to receive(:days_held).and_return(21)
        allow(position).to receive(:update_current_price!)
        allow(AlgoConfig).to receive(:fetch).and_return(20)
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it 'exits the position' do
        expect do
          described_class.new(portfolio: portfolio).check_exits
        end.to change { position.reload.status }.from('open').to('closed')
      end

      it 'sets exit reason to time_based' do
        described_class.new(portfolio: portfolio).check_exits

        position.reload
        expect(position.exit_reason).to eq('time_based')
      end
    end

    context 'when position does not meet exit conditions' do
      let(:position) do
        create(:paper_position,
          paper_portfolio: portfolio,
          instrument: instrument,
          entry_price: 100.0,
          current_price: 100.0,
          sl: 95.0,
          tp: 110.0,
          opened_at: 5.days.ago,
          status: 'open')
      end

      before do
        position
        allow(position).to receive(:check_sl_hit?).and_return(false)
        allow(position).to receive(:check_tp_hit?).and_return(false)
        allow(position).to receive(:days_held).and_return(5)
        allow(position).to receive(:update_current_price!)
        allow(AlgoConfig).to receive(:fetch).and_return(20)
      end

      it 'does not exit the position' do
        expect do
          described_class.new(portfolio: portfolio).check_exits
        end.not_to change { position.reload.status }
      end
    end

    context 'when exit check fails' do
      before do
        allow(portfolio).to receive(:open_positions).and_raise(StandardError, 'Database error')
      end

      it 'raises error' do
        expect do
          described_class.new(portfolio: portfolio).check_exits
        end.to raise_error(StandardError, 'Database error')
      end
    end

    context 'with short positions' do
      let(:short_position) do
        create(:paper_position,
          paper_portfolio: portfolio,
          instrument: instrument,
          direction: 'short',
          entry_price: 100.0,
          current_price: 100.0,
          sl: 105.0,
          tp: 95.0,
          status: 'open')
      end

      before do
        short_position
        allow(short_position).to receive(:update_current_price!)
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it 'exits short position when SL hit (price goes up)' do
        short_position.update(current_price: 106.0)
        allow(short_position).to receive(:check_sl_hit?).and_return(true)
        allow(short_position).to receive(:check_tp_hit?).and_return(false)

        described_class.new(portfolio: portfolio).check_exits

        short_position.reload
        expect(short_position.status).to eq('closed')
        expect(short_position.exit_reason).to eq('sl_hit')
        expect(short_position.pnl).to be < 0 # Loss on short when price goes up
      end

      it 'exits short position when TP hit (price goes down)' do
        short_position.update(current_price: 94.0)
        allow(short_position).to receive(:check_sl_hit?).and_return(false)
        allow(short_position).to receive(:check_tp_hit?).and_return(true)

        described_class.new(portfolio: portfolio).check_exits

        short_position.reload
        expect(short_position.status).to eq('closed')
        expect(short_position.exit_reason).to eq('tp_hit')
        expect(short_position.pnl).to be > 0 # Profit on short when price goes down
      end

      it 'calculates loss correctly for short position' do
        short_position.update(current_price: 106.0)
        allow(short_position).to receive(:check_sl_hit?).and_return(true)
        allow(short_position).to receive(:check_tp_hit?).and_return(false)

        described_class.new(portfolio: portfolio).check_exits

        short_position.reload
        expected_pnl = (100.0 - 105.0) * short_position.quantity # Entry - Exit for short
        expect(short_position.pnl).to eq(expected_pnl)
        expect(short_position.pnl_pct).to be < 0
      end
    end

    context 'with loss scenarios' do
      let(:losing_position) do
        create(:paper_position,
          paper_portfolio: portfolio,
          instrument: instrument,
          entry_price: 100.0,
          current_price: 100.0,
          sl: 95.0,
          status: 'open')
      end

      before do
        losing_position
        create(:candle_series_record,
          instrument: instrument,
          timeframe: '1D',
          close: 94.0,
          timestamp: Time.current)
        allow(losing_position).to receive(:check_sl_hit?).and_return(true)
        allow(losing_position).to receive(:update_current_price!)
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it 'decrements capital on loss' do
        initial_capital = portfolio.capital
        entry_value = losing_position.entry_price * losing_position.quantity
        expected_loss = (95.0 - 100.0) * losing_position.quantity

        described_class.new(portfolio: portfolio).check_exits

        portfolio.reload
        expect(portfolio.capital).to eq(initial_capital - expected_loss.abs)
      end

      it 'creates debit ledger entry for loss' do
        expect do
          described_class.new(portfolio: portfolio).check_exits
        end.to change(PaperLedger, :count).by(1)

        ledger = PaperLedger.last
        expect(ledger.transaction_type).to eq('debit')
        expect(ledger.reason).to eq('loss')
      end
    end

    context 'when no candle available for price update' do
      let(:position) do
        create(:paper_position,
          paper_portfolio: portfolio,
          instrument: instrument,
          entry_price: 100.0,
          current_price: 100.0,
          status: 'open')
      end

      before do
        position
        # No candles created
        allow(position).to receive(:check_sl_hit?).and_return(false)
        allow(position).to receive(:check_tp_hit?).and_return(false)
        allow(position).to receive(:days_held).and_return(5)
        allow(AlgoConfig).to receive(:fetch).and_return(20)
      end

      it 'skips price update but still checks exit conditions' do
        result = described_class.new(portfolio: portfolio).check_exits

        expect(result[:checked]).to eq(1)
        expect(result[:exited]).to eq(0)
      end
    end
  end
end

