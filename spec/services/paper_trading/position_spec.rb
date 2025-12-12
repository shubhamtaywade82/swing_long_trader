# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaperTrading::Position, type: :service do
  let(:portfolio) { create(:paper_portfolio, capital: 100_000, available_capital: 100_000) }
  let(:instrument) { create(:instrument) }
  let(:signal) do
    {
      direction: 'long',
      entry_price: 100.0,
      qty: 10,
      sl: 95.0,
      tp: 110.0,
      metadata: { source: 'test' }
    }
  end

  describe '.create' do
    it 'creates a paper position' do
      expect do
        described_class.create(
          portfolio: portfolio,
          instrument: instrument,
          signal: signal
        )
      end.to change(PaperPosition, :count).by(1)
    end

    it 'creates position with correct attributes' do
      position = described_class.create(
        portfolio: portfolio,
        instrument: instrument,
        signal: signal
      )

      expect(position.paper_portfolio).to eq(portfolio)
      expect(position.instrument).to eq(instrument)
      expect(position.direction).to eq('long')
      expect(position.entry_price).to eq(100.0)
      expect(position.current_price).to eq(100.0)
      expect(position.quantity).to eq(10)
      expect(position.sl).to eq(95.0)
      expect(position.tp).to eq(110.0)
      expect(position.status).to eq('open')
    end

    it 'reserves capital' do
      initial_reserved = portfolio.reserved_capital
      position_value = signal[:entry_price] * signal[:qty]

      described_class.create(
        portfolio: portfolio,
        instrument: instrument,
        signal: signal
      )

      portfolio.reload
      expect(portfolio.reserved_capital).to eq(initial_reserved + position_value)
    end

    it 'updates portfolio equity' do
      allow(portfolio).to receive(:update_equity!)

      described_class.create(
        portfolio: portfolio,
        instrument: instrument,
        signal: signal
      )

      expect(portfolio).to have_received(:update_equity!)
    end

    it 'creates ledger entry for audit trail' do
      expect do
        described_class.create(
          portfolio: portfolio,
          instrument: instrument,
          signal: signal
        )
      end.to change(PaperLedger, :count).by(1)

      ledger = PaperLedger.last
      expect(ledger.transaction_type).to eq('debit')
      expect(ledger.reason).to eq('trade_entry')
      expect(ledger.amount).to eq(1000.0) # entry_price * qty
    end

    it 'stores metadata as JSON' do
      position = described_class.create(
        portfolio: portfolio,
        instrument: instrument,
        signal: signal
      )

      metadata = JSON.parse(position.metadata)
      expect(metadata['source']).to eq('test')
    end

    context 'when metadata is not provided' do
      let(:signal_without_metadata) do
        {
          direction: 'long',
          entry_price: 100.0,
          qty: 10
        }
      end

      it 'stores empty hash as JSON' do
        position = described_class.create(
          portfolio: portfolio,
          instrument: instrument,
          signal: signal_without_metadata
        )

        metadata = JSON.parse(position.metadata)
        expect(metadata).to eq({})
      end
    end

    context 'when creation fails' do
      before do
        allow(PaperPosition).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(PaperPosition.new))
        allow(Rails.logger).to receive(:error)
      end

      it 'raises error and logs' do
        expect do
          described_class.create(
            portfolio: portfolio,
            instrument: instrument,
            signal: signal
          )
        end.to raise_error(ActiveRecord::RecordInvalid)

        expect(Rails.logger).to have_received(:error)
      end
    end

    context 'when ledger creation fails' do
      before do
        allow(PaperLedger).to receive(:create!).and_raise(StandardError, 'Ledger error')
        allow(Rails.logger).to receive(:error)
      end

      it 'raises error' do
        expect do
          described_class.create(
            portfolio: portfolio,
            instrument: instrument,
            signal: signal
          )
        end.to raise_error(StandardError, 'Ledger error')
      end
    end

    context 'when portfolio update fails' do
      before do
        allow(portfolio).to receive(:increment!).and_raise(StandardError, 'Update error')
        allow(Rails.logger).to receive(:error)
      end

      it 'raises error' do
        expect do
          described_class.create(
            portfolio: portfolio,
            instrument: instrument,
            signal: signal
          )
        end.to raise_error(StandardError, 'Update error')
      end
    end

    context 'with short direction' do
      let(:short_signal) do
        {
          direction: 'short',
          entry_price: 100.0,
          qty: 10,
          sl: 105.0,
          tp: 90.0
        }
      end

      it 'creates short position' do
        position = described_class.create(
          portfolio: portfolio,
          instrument: instrument,
          signal: short_signal
        )

        expect(position.direction).to eq('short')
        expect(position.sl).to eq(105.0)
        expect(position.tp).to eq(90.0)
      end
    end

    context 'with symbol direction' do
      let(:symbol_signal) do
        {
          direction: :long,
          entry_price: 100.0,
          qty: 10
        }
      end

      it 'converts symbol direction to string' do
        position = described_class.create(
          portfolio: portfolio,
          instrument: instrument,
          signal: symbol_signal
        )

        expect(position.direction).to eq('long')
      end
    end

    context 'when signal has nil SL or TP' do
      let(:signal_no_sl_tp) do
        {
          direction: 'long',
          entry_price: 100.0,
          qty: 10,
          sl: nil,
          tp: nil
        }
      end

      it 'creates position with nil SL and TP' do
        position = described_class.create(
          portfolio: portfolio,
          instrument: instrument,
          signal: signal_no_sl_tp
        )

        expect(position.sl).to be_nil
        expect(position.tp).to be_nil
      end
    end

    it 'logs creation info' do
      allow(Rails.logger).to receive(:info)
      described_class.create(
        portfolio: portfolio,
        instrument: instrument,
        signal: signal
      )

      expect(Rails.logger).to have_received(:info).with(/Created paper position/)
    end

    it 'creates ledger with correct meta information' do
      described_class.create(
        portfolio: portfolio,
        instrument: instrument,
        signal: signal
      )

      ledger = PaperLedger.last
      meta = JSON.parse(ledger.meta)
      expect(meta['symbol']).to eq(instrument.symbol_name)
      expect(meta['direction']).to eq('long')
      expect(meta['entry_price']).to eq(100.0)
      expect(meta['quantity']).to eq(10)
    end
  end

  describe '#reserve_capital' do
    it 'increments reserved capital' do
      initial_reserved = portfolio.reserved_capital
      service = described_class.new(portfolio: portfolio, instrument: instrument, signal: signal)

      service.send(:reserve_capital, 5000.0)

      portfolio.reload
      expect(portfolio.reserved_capital).to eq(initial_reserved + 5000.0)
    end

    it 'updates portfolio equity after reserving' do
      allow(portfolio).to receive(:update_equity!)
      service = described_class.new(portfolio: portfolio, instrument: instrument, signal: signal)

      service.send(:reserve_capital, 5000.0)

      expect(portfolio).to have_received(:update_equity!)
    end
  end
end

