# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaperTrading::Executor, type: :service do
  let(:portfolio) { create(:paper_portfolio, capital: 100_000, available_capital: 100_000) }
  let(:instrument) { create(:instrument) }
  let(:signal) do
    {
      instrument_id: instrument.id,
      direction: 'long',
      entry_price: 100.0,
      qty: 10,
      sl: 95.0,
      tp: 110.0
    }
  end

  describe '.execute' do
    context 'when portfolio is provided' do
      it 'uses provided portfolio' do
        allow(PaperTrading::Portfolio).to receive(:find_or_create_default)
        allow_any_instance_of(described_class).to receive(:execute).and_return({ success: true })

        described_class.execute(signal, portfolio: portfolio)

        expect(PaperTrading::Portfolio).not_to have_received(:find_or_create_default)
      end
    end

    context 'when portfolio is not provided' do
      let(:default_portfolio) { create(:paper_portfolio, name: 'default') }

      before do
        allow(PaperTrading::Portfolio).to receive(:find_or_create_default).and_return(default_portfolio)
        allow_any_instance_of(described_class).to receive(:execute).and_return({ success: true })
      end

      it 'uses default portfolio' do
        described_class.execute(signal)

        expect(PaperTrading::Portfolio).to have_received(:find_or_create_default)
      end
    end
  end

  describe '#execute' do
    context 'when signal is valid' do
      before do
        allow(PaperTrading::RiskManager).to receive(:check_limits).and_return({ success: true })
        allow(PaperTrading::Position).to receive(:create).and_return(
          create(:paper_position, paper_portfolio: portfolio, instrument: instrument)
        )
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it 'creates a position' do
        expect(PaperTrading::Position).to receive(:create).with(
          portfolio: portfolio,
          instrument: instrument,
          signal: signal
        )

        described_class.new(signal: signal, portfolio: portfolio).execute
      end

      it 'returns success' do
        result = described_class.new(signal: signal, portfolio: portfolio).execute

        expect(result[:success]).to be true
        expect(result[:position]).to be_present
        expect(result[:message]).to include(instrument.symbol_name)
      end

      it 'sends entry notification' do
        allow(Telegram::Notifier).to receive(:enabled?).and_return(true)
        allow(Telegram::Notifier).to receive(:send_error_alert)

        described_class.new(signal: signal, portfolio: portfolio).execute

        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end
    end

    context 'when signal validation fails' do
      context 'when signal is missing' do
        it 'returns error' do
          result = described_class.new(signal: nil, portfolio: portfolio).execute

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Invalid signal')
        end
      end

      context 'when instrument is not found' do
        let(:signal) do
          {
            instrument_id: 99999,
            direction: 'long',
            entry_price: 100.0,
            qty: 10
          }
        end

        it 'returns error' do
          result = described_class.new(signal: signal, portfolio: portfolio).execute

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Instrument not found')
        end
      end

      context 'when entry_price is missing' do
        let(:signal) do
          {
            instrument_id: instrument.id,
            direction: 'long',
            qty: 10
          }
        end

        it 'returns error' do
          result = described_class.new(signal: signal, portfolio: portfolio).execute

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Missing entry price')
        end
      end

      context 'when quantity is missing' do
        let(:signal) do
          {
            instrument_id: instrument.id,
            direction: 'long',
            entry_price: 100.0
          }
        end

        it 'returns error' do
          result = described_class.new(signal: signal, portfolio: portfolio).execute

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Missing quantity')
        end
      end

      context 'when direction is missing' do
        let(:signal) do
          {
            instrument_id: instrument.id,
            entry_price: 100.0,
            qty: 10
          }
        end

        it 'returns error' do
          result = described_class.new(signal: signal, portfolio: portfolio).execute

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Missing direction')
        end
      end
    end

    context 'when risk check fails' do
      before do
        allow(PaperTrading::RiskManager).to receive(:check_limits).and_return(
          { success: false, error: 'Risk limit exceeded' }
        )
      end

      it 'returns risk check error' do
        result = described_class.new(signal: signal, portfolio: portfolio).execute

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Risk limit exceeded')
      end
    end

    context 'when execution fails' do
      before do
        allow(PaperTrading::RiskManager).to receive(:check_limits).and_return({ success: true })
        allow(PaperTrading::Position).to receive(:create).and_raise(StandardError, 'Database error')
      end

      it 'returns error' do
        result = described_class.new(signal: signal, portfolio: portfolio).execute

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Database error')
      end
    end

    context 'when notification sending fails' do
      before do
        allow(PaperTrading::RiskManager).to receive(:check_limits).and_return({ success: true })
        allow(PaperTrading::Position).to receive(:create).and_return(
          create(:paper_position, paper_portfolio: portfolio, instrument: instrument)
        )
        allow(Telegram::Notifier).to receive(:enabled?).and_return(true)
        allow(Telegram::Notifier).to receive(:send_error_alert).and_raise(StandardError, 'Telegram error')
      end

      it 'still returns success' do
        result = described_class.new(signal: signal, portfolio: portfolio).execute

        expect(result[:success]).to be true
        expect(result[:position]).to be_present
      end
    end

    context 'when signal has optional fields' do
      let(:signal_with_optional) do
        {
          instrument_id: instrument.id,
          direction: 'long',
          entry_price: 100.0,
          qty: 10,
          sl: 95.0,
          tp: 110.0,
          metadata: { test: 'value' }
        }
      end

      before do
        allow(PaperTrading::RiskManager).to receive(:check_limits).and_return({ success: true })
        allow(PaperTrading::Position).to receive(:create).and_return(
          create(:paper_position, paper_portfolio: portfolio, instrument: instrument)
        )
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it 'handles signal with optional fields' do
        result = described_class.new(signal: signal_with_optional, portfolio: portfolio).execute

        expect(result[:success]).to be true
      end
    end
  end

  describe '#send_entry_notification' do
    let(:position) { create(:paper_position, paper_portfolio: portfolio, instrument: instrument) }

    context 'when Telegram is enabled' do
      before do
        allow(Telegram::Notifier).to receive(:enabled?).and_return(true)
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'sends notification with all signal details' do
        executor = described_class.new(signal: signal, portfolio: portfolio)
        executor.send(:send_entry_notification, position)

        expect(Telegram::Notifier).to have_received(:send_error_alert).with(
          a_string_including(instrument.symbol_name),
          context: 'Paper Trade Entry'
        )
      end

      it 'handles signal without SL' do
        signal_no_sl = signal.dup
        signal_no_sl.delete(:sl)
        executor = described_class.new(signal: signal_no_sl, portfolio: portfolio)
        executor.send(:send_entry_notification, position)

        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end

      it 'handles signal without TP' do
        signal_no_tp = signal.dup
        signal_no_tp.delete(:tp)
        executor = described_class.new(signal: signal_no_tp, portfolio: portfolio)
        executor.send(:send_entry_notification, position)

        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end
    end

    context 'when Telegram is disabled' do
      before do
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'does not send notification' do
        executor = described_class.new(signal: signal, portfolio: portfolio)
        executor.send(:send_entry_notification, position)

        expect(Telegram::Notifier).not_to have_received(:send_error_alert)
      end
    end
  end
end

