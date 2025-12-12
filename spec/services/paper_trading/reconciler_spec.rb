# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaperTrading::Reconciler, type: :service do
  let(:portfolio) { create(:paper_portfolio, capital: 100_000) }
  let(:instrument) { create(:instrument) }

  describe '.call' do
    context 'when portfolio is provided' do
      it 'uses provided portfolio' do
        allow(PaperTrading::Portfolio).to receive(:find_or_create_default)
        allow_any_instance_of(described_class).to receive(:call).and_return({})

        described_class.call(portfolio: portfolio)

        expect(PaperTrading::Portfolio).not_to have_received(:find_or_create_default)
      end
    end

    context 'when portfolio is not provided' do
      let(:default_portfolio) { create(:paper_portfolio, name: 'default') }

      before do
        allow(PaperTrading::Portfolio).to receive(:find_or_create_default).and_return(default_portfolio)
        allow_any_instance_of(described_class).to receive(:call).and_return({})
      end

      it 'uses default portfolio' do
        described_class.call

        expect(PaperTrading::Portfolio).to have_received(:find_or_create_default)
      end
    end
  end

  describe '#call' do
    context 'when there are no open positions' do
      before do
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it 'returns summary with zero positions' do
        result = described_class.new(portfolio: portfolio).call

        expect(result[:open_positions_count]).to eq(0)
        expect(result[:closed_positions_count]).to eq(0)
        expect(result[:pnl_unrealized]).to eq(0)
      end

      it 'updates portfolio equity' do
        allow(portfolio).to receive(:update_equity!)

        described_class.new(portfolio: portfolio).call

        expect(portfolio).to have_received(:update_equity!)
      end

      it 'updates portfolio drawdown' do
        allow(portfolio).to receive(:update_drawdown!)

        described_class.new(portfolio: portfolio).call

        expect(portfolio).to have_received(:update_drawdown!)
      end
    end

    context 'when there are open positions' do
      let(:position1) do
        create(:paper_position,
          paper_portfolio: portfolio,
          instrument: instrument,
          entry_price: 100.0,
          current_price: 105.0,
          quantity: 10,
          status: 'open')
      end

      let(:position2) do
        create(:paper_position,
          paper_portfolio: portfolio,
          instrument: create(:instrument),
          entry_price: 50.0,
          current_price: 48.0,
          quantity: 20,
          status: 'open')
      end

      before do
        position1
        position2
        create(:candle_series_record,
          instrument: position1.instrument,
          timeframe: '1D',
          close: 105.0,
          timestamp: Time.current)
        create(:candle_series_record,
          instrument: position2.instrument,
          timeframe: '1D',
          close: 48.0,
          timestamp: Time.current)
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it 'updates all position prices' do
        expect(position1).to receive(:update_current_price!).with(105.0)
        expect(position2).to receive(:update_current_price!).with(48.0)

        described_class.new(portfolio: portfolio).call
      end

      it 'calculates unrealized P&L' do
        result = described_class.new(portfolio: portfolio).call

        # Position 1: (105 - 100) * 10 = 50 profit
        # Position 2: (48 - 50) * 20 = -40 loss
        # Total: 50 - 40 = 10
        expect(result[:pnl_unrealized]).to eq(10.0)
      end

      it 'returns summary with position counts' do
        result = described_class.new(portfolio: portfolio).call

        expect(result[:open_positions_count]).to eq(2)
        expect(result[:total_exposure]).to be > 0
      end
    end

    context 'when there are closed positions' do
      before do
        create(:paper_position,
          paper_portfolio: portfolio,
          status: 'closed')
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it 'includes closed positions in summary' do
        result = described_class.new(portfolio: portfolio).call

        expect(result[:closed_positions_count]).to eq(1)
      end
    end

    context 'when sending daily summary' do
      before do
        allow(Telegram::Notifier).to receive(:enabled?).and_return(true)
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'sends Telegram notification' do
        described_class.new(portfolio: portfolio).call

        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end

      it 'includes portfolio metrics in message' do
        described_class.new(portfolio: portfolio).call

        expect(Telegram::Notifier).to have_received(:send_error_alert) do |message|
          expect(message).to include('DAILY PAPER TRADING SUMMARY')
          expect(message).to include('Capital')
          expect(message).to include('Total Equity')
        end
      end
    end

    context 'when reconciliation fails' do
      before do
        allow(portfolio).to receive(:open_positions).and_raise(StandardError, 'Database error')
      end

      it 'raises error' do
        expect do
          described_class.new(portfolio: portfolio).call
        end.to raise_error(StandardError, 'Database error')
      end
    end
  end
end

