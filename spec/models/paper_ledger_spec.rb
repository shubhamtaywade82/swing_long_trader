# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaperLedger, type: :model do
  let(:portfolio) { create(:paper_portfolio) }
  let(:ledger) do
    create(:paper_ledger,
      paper_portfolio: portfolio,
      amount: 1000.0,
      transaction_type: 'credit',
      reason: 'Initial deposit')
  end

  describe 'validations' do
    it 'requires amount' do
      ledger = PaperLedger.new(
        paper_portfolio: portfolio,
        transaction_type: 'credit',
        reason: 'Test'
      )
      expect(ledger).not_to be_valid
      expect(ledger.errors[:amount]).to include("can't be blank")
    end

    it 'requires amount to be > 0' do
      ledger = PaperLedger.new(
        paper_portfolio: portfolio,
        amount: -100,
        transaction_type: 'credit',
        reason: 'Test'
      )
      expect(ledger).not_to be_valid
      expect(ledger.errors[:amount]).to be_present
    end

    it 'requires transaction_type' do
      ledger = PaperLedger.new(
        paper_portfolio: portfolio,
        amount: 1000,
        reason: 'Test'
      )
      expect(ledger).not_to be_valid
      expect(ledger.errors[:transaction_type]).to include("can't be blank")
    end

    it 'requires transaction_type to be credit or debit' do
      ledger = PaperLedger.new(
        paper_portfolio: portfolio,
        amount: 1000,
        transaction_type: 'invalid',
        reason: 'Test'
      )
      expect(ledger).not_to be_valid
      expect(ledger.errors[:transaction_type]).to be_present
    end
  end

  describe 'scopes' do
    it 'filters by transaction type' do
      credit = create(:paper_ledger, paper_portfolio: portfolio, transaction_type: 'credit')
      debit = create(:paper_ledger, paper_portfolio: portfolio, transaction_type: 'debit')

      expect(PaperLedger.credits).to include(credit)
      expect(PaperLedger.credits).not_to include(debit)
      expect(PaperLedger.debits).to include(debit)
      expect(PaperLedger.debits).not_to include(credit)
    end
  end

  describe '#credit?' do
    it 'returns true for credit transactions' do
      expect(ledger.credit?).to be true
    end

    it 'returns false for debit transactions' do
      ledger.update(transaction_type: 'debit')
      expect(ledger.credit?).to be false
    end
  end

  describe '#debit?' do
    it 'returns true for debit transactions' do
      ledger.update(transaction_type: 'debit')
      expect(ledger.debit?).to be true
    end
  end

  describe '#meta_hash' do
    it 'returns parsed JSON meta' do
      ledger.update(meta: '{"key": "value"}')
      expect(ledger.meta_hash).to eq({ 'key' => 'value' })
    end

    it 'returns empty hash for blank meta' do
      expect(ledger.meta_hash).to eq({})
    end

    it 'returns empty hash for invalid JSON' do
      ledger.update(meta: 'invalid json')
      expect(ledger.meta_hash).to eq({})
    end
  end
end

