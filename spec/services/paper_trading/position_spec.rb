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
      end

      it 'raises error' do
        expect do
          described_class.create(
            portfolio: portfolio,
            instrument: instrument,
            signal: signal
          )
        end.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end
end

