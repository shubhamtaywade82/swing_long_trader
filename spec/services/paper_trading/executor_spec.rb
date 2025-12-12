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

    describe 'private methods' do
      describe '#validate_signal' do
        it 'validates signal with all required fields' do
          executor = described_class.new(signal: signal, portfolio: portfolio)
          result = executor.send(:validate_signal)

          expect(result[:success]).to be true
        end

        it 'rejects nil signal' do
          executor = described_class.new(signal: nil, portfolio: portfolio)
          result = executor.send(:validate_signal)

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Invalid signal')
        end

        it 'rejects signal without instrument_id' do
          invalid_signal = signal.dup
          invalid_signal[:instrument_id] = nil
          executor = described_class.new(signal: invalid_signal, portfolio: portfolio)
          result = executor.send(:validate_signal)

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Instrument not found')
        end

        it 'rejects signal without entry_price' do
          invalid_signal = signal.dup
          invalid_signal.delete(:entry_price)
          executor = described_class.new(signal: invalid_signal, portfolio: portfolio)
          result = executor.send(:validate_signal)

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Missing entry price')
        end

        it 'rejects signal without qty' do
          invalid_signal = signal.dup
          invalid_signal.delete(:qty)
          executor = described_class.new(signal: invalid_signal, portfolio: portfolio)
          result = executor.send(:validate_signal)

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Missing quantity')
        end

        it 'rejects signal without direction' do
          invalid_signal = signal.dup
          invalid_signal.delete(:direction)
          executor = described_class.new(signal: invalid_signal, portfolio: portfolio)
          result = executor.send(:validate_signal)

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Missing direction')
        end

        it 'rejects signal with non-existent instrument' do
          invalid_signal = signal.dup
          invalid_signal[:instrument_id] = 99999
          executor = described_class.new(signal: invalid_signal, portfolio: portfolio)
          result = executor.send(:validate_signal)

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Instrument not found')
        end
      end

      describe '#send_entry_notification' do
        let(:position) { create(:paper_position, paper_portfolio: portfolio, instrument: instrument) }

        it 'includes all signal details in notification' do
          allow(Telegram::Notifier).to receive(:enabled?).and_return(true)
          allow(Telegram::Notifier).to receive(:send_error_alert)

          executor = described_class.new(signal: signal, portfolio: portfolio)
          executor.send(:send_entry_notification, position)

          expect(Telegram::Notifier).to have_received(:send_error_alert) do |message, options|
            expect(message).to include(instrument.symbol_name)
            expect(message).to include('LONG')
            expect(message).to include('100.0')
            expect(message).to include('95.0')
            expect(message).to include('110.0')
            expect(message).to include('10')
            expect(options[:context]).to eq('Paper Trade Entry')
          end
        end

        it 'handles notification failure gracefully' do
          allow(Telegram::Notifier).to receive(:enabled?).and_return(true)
          allow(Telegram::Notifier).to receive(:send_error_alert).and_raise(StandardError, 'Telegram error')
          allow(Rails.logger).to receive(:error)

          executor = described_class.new(signal: signal, portfolio: portfolio)
          executor.send(:send_entry_notification, position)

          expect(Rails.logger).to have_received(:error)
        end

        it 'calculates capital used correctly' do
          allow(Telegram::Notifier).to receive(:enabled?).and_return(true)
          allow(Telegram::Notifier).to receive(:send_error_alert)

          executor = described_class.new(signal: signal, portfolio: portfolio)
          executor.send(:send_entry_notification, position)

          expect(Telegram::Notifier).to have_received(:send_error_alert) do |message|
            # Capital used = 100.0 * 10 = 1000.0
            expect(message).to include('1000')
          end
        end

        it 'includes portfolio equity in notification' do
          allow(Telegram::Notifier).to receive(:enabled?).and_return(true)
          allow(Telegram::Notifier).to receive(:send_error_alert)
          allow(portfolio).to receive(:total_equity).and_return(50_000.0)

          executor = described_class.new(signal: signal, portfolio: portfolio)
          executor.send(:send_entry_notification, position)

          expect(Telegram::Notifier).to have_received(:send_error_alert) do |message|
            expect(message).to include('50000')
          end
        end
      end
    end

    context 'with edge cases' do
      it 'handles position creation failure' do
        allow(PaperTrading::RiskManager).to receive(:check_limits).and_return({ success: true })
        allow(PaperTrading::Position).to receive(:create).and_raise(StandardError, 'Position creation failed')
        allow(Rails.logger).to receive(:error)

        result = described_class.new(signal: signal, portfolio: portfolio).execute

        expect(result[:success]).to be false
        expect(result[:error]).to include('Position creation failed')
        expect(Rails.logger).to have_received(:error)
      end

      it 'handles signal with zero quantity' do
        signal_zero_qty = signal.dup
        signal_zero_qty[:qty] = 0

        result = described_class.new(signal: signal_zero_qty, portfolio: portfolio).execute

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Missing quantity')
      end

      it 'handles signal with negative entry price' do
        signal_negative = signal.dup
        signal_negative[:entry_price] = -100.0

        allow(PaperTrading::RiskManager).to receive(:check_limits).and_return({ success: true })
        allow(PaperTrading::Position).to receive(:create).and_return(
          create(:paper_position, paper_portfolio: portfolio, instrument: instrument)
        )
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)

        result = described_class.new(signal: signal_negative, portfolio: portfolio).execute

        # Should still execute (validation doesn't check for negative prices)
        expect(result[:success]).to be true
      end
    end
  end
end

