# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::Ledger, type: :service do
  let(:portfolio) { create(:paper_portfolio, capital: 100_000, available_capital: 100_000) }

  describe ".credit" do
    it "creates a credit ledger entry" do
      expect do
        described_class.credit(
          portfolio: portfolio,
          amount: 5000,
          reason: "test_credit",
          description: "Test credit entry",
        )
      end.to change(PaperLedger, :count).by(1)
    end

    it "creates entry with correct attributes" do
      ledger = described_class.credit(
        portfolio: portfolio,
        amount: 5000,
        reason: "test_credit",
        description: "Test credit entry",
      )

      expect(ledger.paper_portfolio).to eq(portfolio)
      expect(ledger.transaction_type).to eq("credit")
      expect(ledger.amount).to eq(5000)
      expect(ledger.reason).to eq("test_credit")
      expect(ledger.description).to eq("Test credit entry")
    end

    it "increases portfolio capital" do
      initial_capital = portfolio.capital

      described_class.credit(
        portfolio: portfolio,
        amount: 5000,
        reason: "test_credit",
      )

      portfolio.reload
      expect(portfolio.capital).to eq(initial_capital + 5000)
    end

    it "updates portfolio equity" do
      allow(portfolio).to receive(:update_equity!)

      described_class.credit(
        portfolio: portfolio,
        amount: 5000,
        reason: "test_credit",
      )

      expect(portfolio).to have_received(:update_equity!)
    end

    context "when position is provided" do
      let(:position) { create(:paper_position, paper_portfolio: portfolio) }

      it "associates ledger entry with position" do
        ledger = described_class.credit(
          portfolio: portfolio,
          amount: 5000,
          reason: "profit",
          position: position,
        )

        expect(ledger.paper_position).to eq(position)
      end
    end

    context "when meta is provided" do
      it "stores meta as JSON" do
        meta = { symbol: "RELIANCE", price: 2500 }
        ledger = described_class.credit(
          portfolio: portfolio,
          amount: 5000,
          reason: "test_credit",
          meta: meta,
        )

        expect(JSON.parse(ledger.meta)).to eq(meta.stringify_keys)
      end
    end
  end

  describe ".debit" do
    it "creates a debit ledger entry" do
      expect do
        described_class.debit(
          portfolio: portfolio,
          amount: 3000,
          reason: "test_debit",
          description: "Test debit entry",
        )
      end.to change(PaperLedger, :count).by(1)
    end

    it "creates entry with correct attributes" do
      ledger = described_class.debit(
        portfolio: portfolio,
        amount: 3000,
        reason: "test_debit",
        description: "Test debit entry",
      )

      expect(ledger.paper_portfolio).to eq(portfolio)
      expect(ledger.transaction_type).to eq("debit")
      expect(ledger.amount).to eq(3000)
      expect(ledger.reason).to eq("test_debit")
      expect(ledger.description).to eq("Test debit entry")
    end

    it "decreases portfolio capital" do
      initial_capital = portfolio.capital

      described_class.debit(
        portfolio: portfolio,
        amount: 3000,
        reason: "test_debit",
      )

      portfolio.reload
      expect(portfolio.capital).to eq(initial_capital - 3000)
    end

    it "updates portfolio equity" do
      allow(portfolio).to receive(:update_equity!)

      described_class.debit(
        portfolio: portfolio,
        amount: 3000,
        reason: "test_debit",
      )

      expect(portfolio).to have_received(:update_equity!)
    end
  end

  describe "#record" do
    context "when recording fails" do
      before do
        allow(PaperLedger).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(PaperLedger.new))
      end

      it "raises error" do
        service = described_class.new(
          portfolio: portfolio,
          amount: 1000,
          transaction_type: "credit",
          reason: "test",
        )

        expect { service.record }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context "with edge cases" do
      it "handles zero amount" do
        ledger = described_class.credit(
          portfolio: portfolio,
          amount: 0,
          reason: "zero_credit",
        )

        expect(ledger.amount).to eq(0)
        expect(portfolio.reload.capital).to eq(portfolio.capital)
      end

      it "handles very large amounts" do
        large_amount = 1_000_000_000
        ledger = described_class.credit(
          portfolio: portfolio,
          amount: large_amount,
          reason: "large_credit",
        )

        expect(ledger.amount).to eq(large_amount.to_f)
        expect(portfolio.reload.capital).to eq(portfolio.capital + large_amount)
      end

      it "handles negative amounts gracefully" do
        # Negative amounts should be handled by the service
        ledger = described_class.credit(
          portfolio: portfolio,
          amount: -1000,
          reason: "negative_credit",
        )

        expect(ledger.amount).to eq(-1000.0)
        # Capital should decrease (negative credit)
        expect(portfolio.reload.capital).to eq(portfolio.capital - 1000)
      end

      it "handles string amounts" do
        ledger = described_class.credit(
          portfolio: portfolio,
          amount: "5000",
          reason: "string_amount",
        )

        expect(ledger.amount).to eq(5000.0)
      end

      it "handles nil description" do
        ledger = described_class.credit(
          portfolio: portfolio,
          amount: 1000,
          reason: "no_description",
          description: nil,
        )

        expect(ledger.description).to be_nil
      end

      it "handles empty meta" do
        ledger = described_class.credit(
          portfolio: portfolio,
          amount: 1000,
          reason: "empty_meta",
          meta: {},
        )

        expect(JSON.parse(ledger.meta)).to eq({})
      end

      it "handles nil meta" do
        ledger = described_class.credit(
          portfolio: portfolio,
          amount: 1000,
          reason: "nil_meta",
          meta: nil,
        )

        expect(ledger.meta).to be_present
      end
    end

    context "with multiple transactions" do
      it "tracks multiple credits correctly" do
        initial_capital = portfolio.capital

        described_class.credit(portfolio: portfolio, amount: 1000, reason: "credit1")
        described_class.credit(portfolio: portfolio, amount: 2000, reason: "credit2")
        described_class.credit(portfolio: portfolio, amount: 3000, reason: "credit3")

        portfolio.reload
        expect(portfolio.capital).to eq(initial_capital + 6000)
        expect(PaperLedger.credits.count).to eq(3)
      end

      it "tracks multiple debits correctly" do
        initial_capital = portfolio.capital

        described_class.debit(portfolio: portfolio, amount: 1000, reason: "debit1")
        described_class.debit(portfolio: portfolio, amount: 2000, reason: "debit2")
        described_class.debit(portfolio: portfolio, amount: 3000, reason: "debit3")

        portfolio.reload
        expect(portfolio.capital).to eq(initial_capital - 6000)
        expect(PaperLedger.debits.count).to eq(3)
      end

      it "tracks mixed credits and debits correctly" do
        initial_capital = portfolio.capital

        described_class.credit(portfolio: portfolio, amount: 5000, reason: "credit")
        described_class.debit(portfolio: portfolio, amount: 2000, reason: "debit")
        described_class.credit(portfolio: portfolio, amount: 1000, reason: "credit2")

        portfolio.reload
        expect(portfolio.capital).to eq(initial_capital + 4000) # 5000 - 2000 + 1000
      end
    end

    context "with position association" do
      let(:position) { create(:paper_position, paper_portfolio: portfolio) }

      it "associates credit with position" do
        ledger = described_class.credit(
          portfolio: portfolio,
          amount: 1000,
          reason: "profit",
          position: position,
        )

        expect(ledger.paper_position).to eq(position)
      end

      it "associates debit with position" do
        ledger = described_class.debit(
          portfolio: portfolio,
          amount: 1000,
          reason: "loss",
          position: position,
        )

        expect(ledger.paper_position).to eq(position)
      end
    end

    context "with logging" do
      it "logs credit transactions" do
        allow(Rails.logger).to receive(:info)

        described_class.credit(
          portfolio: portfolio,
          amount: 1000,
          reason: "test_credit",
        )

        expect(Rails.logger).to have_received(:info).at_least(:once)
      end

      it "logs debit transactions" do
        allow(Rails.logger).to receive(:info)

        described_class.debit(
          portfolio: portfolio,
          amount: 1000,
          reason: "test_debit",
        )

        expect(Rails.logger).to have_received(:info).at_least(:once)
      end

      it "logs errors on failure" do
        allow(PaperLedger).to receive(:create!).and_raise(StandardError.new("Database error"))
        allow(Rails.logger).to receive(:error)

        service = described_class.new(
          portfolio: portfolio,
          amount: 1000,
          transaction_type: "credit",
          reason: "test",
        )

        expect { service.record }.to raise_error(StandardError)
        expect(Rails.logger).to have_received(:error)
      end
    end
  end
end
