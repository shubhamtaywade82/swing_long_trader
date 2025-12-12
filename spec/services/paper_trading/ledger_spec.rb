# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaperTrading::Ledger, type: :service do
  let(:portfolio) { create(:paper_portfolio, capital: 100_000, available_capital: 100_000) }

  describe '.credit' do
    it 'creates a credit ledger entry' do
      expect do
        described_class.credit(
          portfolio: portfolio,
          amount: 5000,
          reason: 'test_credit',
          description: 'Test credit entry'
        )
      end.to change(PaperLedger, :count).by(1)
    end

    it 'creates entry with correct attributes' do
      ledger = described_class.credit(
        portfolio: portfolio,
        amount: 5000,
        reason: 'test_credit',
        description: 'Test credit entry'
      )

      expect(ledger.paper_portfolio).to eq(portfolio)
      expect(ledger.transaction_type).to eq('credit')
      expect(ledger.amount).to eq(5000)
      expect(ledger.reason).to eq('test_credit')
      expect(ledger.description).to eq('Test credit entry')
    end

    it 'increases portfolio capital' do
      initial_capital = portfolio.capital

      described_class.credit(
        portfolio: portfolio,
        amount: 5000,
        reason: 'test_credit'
      )

      portfolio.reload
      expect(portfolio.capital).to eq(initial_capital + 5000)
    end

    it 'updates portfolio equity' do
      allow(portfolio).to receive(:update_equity!)

      described_class.credit(
        portfolio: portfolio,
        amount: 5000,
        reason: 'test_credit'
      )

      expect(portfolio).to have_received(:update_equity!)
    end

    context 'when position is provided' do
      let(:position) { create(:paper_position, paper_portfolio: portfolio) }

      it 'associates ledger entry with position' do
        ledger = described_class.credit(
          portfolio: portfolio,
          amount: 5000,
          reason: 'profit',
          position: position
        )

        expect(ledger.paper_position).to eq(position)
      end
    end

    context 'when meta is provided' do
      it 'stores meta as JSON' do
        meta = { symbol: 'RELIANCE', price: 2500 }
        ledger = described_class.credit(
          portfolio: portfolio,
          amount: 5000,
          reason: 'test_credit',
          meta: meta
        )

        expect(JSON.parse(ledger.meta)).to eq(meta.stringify_keys)
      end
    end
  end

  describe '.debit' do
    it 'creates a debit ledger entry' do
      expect do
        described_class.debit(
          portfolio: portfolio,
          amount: 3000,
          reason: 'test_debit',
          description: 'Test debit entry'
        )
      end.to change(PaperLedger, :count).by(1)
    end

    it 'creates entry with correct attributes' do
      ledger = described_class.debit(
        portfolio: portfolio,
        amount: 3000,
        reason: 'test_debit',
        description: 'Test debit entry'
      )

      expect(ledger.paper_portfolio).to eq(portfolio)
      expect(ledger.transaction_type).to eq('debit')
      expect(ledger.amount).to eq(3000)
      expect(ledger.reason).to eq('test_debit')
      expect(ledger.description).to eq('Test debit entry')
    end

    it 'decreases portfolio capital' do
      initial_capital = portfolio.capital

      described_class.debit(
        portfolio: portfolio,
        amount: 3000,
        reason: 'test_debit'
      )

      portfolio.reload
      expect(portfolio.capital).to eq(initial_capital - 3000)
    end

    it 'updates portfolio equity' do
      allow(portfolio).to receive(:update_equity!)

      described_class.debit(
        portfolio: portfolio,
        amount: 3000,
        reason: 'test_debit'
      )

      expect(portfolio).to have_received(:update_equity!)
    end
  end

  describe '#record' do
    context 'when recording fails' do
      before do
        allow(PaperLedger).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(PaperLedger.new))
      end

      it 'raises error' do
        service = described_class.new(
          portfolio: portfolio,
          amount: 1000,
          transaction_type: 'credit',
          reason: 'test'
        )

        expect { service.record }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end
end

