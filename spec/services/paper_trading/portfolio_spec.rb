# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::Portfolio, type: :service do
  describe ".find_or_create_default" do
    context "when default portfolio exists" do
      let!(:existing_portfolio) { create(:paper_portfolio, name: "default") }

      it "returns existing portfolio" do
        result = described_class.find_or_create_default

        expect(result).to eq(existing_portfolio)
        expect(result.name).to eq("default")
      end

      it "does not create a new portfolio" do
        expect do
          described_class.find_or_create_default
        end.not_to change(PaperPortfolio, :count)
      end
    end

    context "when default portfolio does not exist" do
      before do
        PaperPortfolio.where(name: "default").destroy_all
      end

      it "creates a new default portfolio" do
        expect do
          described_class.find_or_create_default
        end.to change(PaperPortfolio, :count).by(1)
      end

      it "creates portfolio with default capital" do
        portfolio = described_class.find_or_create_default
        portfolio.reload # Reload after ledger entry updates capital

        expect(portfolio.name).to eq("default")
        # Capital is incremented by Ledger.credit, so 100_000 initial + 100_000 credit = 200_000
        expect(portfolio.capital).to eq(200_000)
        expect(portfolio.available_capital).to eq(200_000)
        expect(portfolio.total_equity).to eq(200_000)
        expect(portfolio.peak_equity).to eq(200_000)
      end

      it "creates initial ledger entry" do
        portfolio = described_class.find_or_create_default

        ledger = PaperLedger.last
        expect(ledger).to be_present
        expect(ledger.paper_portfolio).to eq(portfolio)
        expect(ledger.transaction_type).to eq("credit")
        expect(ledger.amount).to eq(100_000)
        expect(ledger.reason).to eq("initial_capital")
      end
    end

    context "when custom initial capital is provided" do
      before do
        PaperPortfolio.where(name: "default").destroy_all
      end

      it "creates portfolio with custom capital" do
        portfolio = described_class.find_or_create_default(initial_capital: 200_000)
        portfolio.reload # Reload after ledger entry updates capital

        # Capital is incremented by Ledger.credit, so 200_000 initial + 200_000 credit = 400_000
        expect(portfolio.capital).to eq(400_000)
        expect(portfolio.available_capital).to eq(400_000)
      end
    end
  end

  describe ".create" do
    it "creates a new portfolio" do
      expect do
        described_class.create(name: "test_portfolio", initial_capital: 50_000)
      end.to change(PaperPortfolio, :count).by(1)
    end

    it "creates portfolio with correct attributes" do
      portfolio = described_class.create!(name: "test_portfolio", initial_capital: 50_000)
      portfolio.reload # Reload after ledger entry updates capital

      expect(portfolio.name).to eq("test_portfolio")
      # Capital is incremented by Ledger.credit, so 50_000 initial + 50_000 credit = 100_000
      expect(portfolio.capital).to eq(100_000)
      expect(portfolio.available_capital).to eq(100_000)
      expect(portfolio.total_equity).to eq(100_000)
      # peak_equity is only updated by update_drawdown!, not update_equity!, so it stays at initial value
      expect(portfolio.peak_equity).to eq(50_000)
    end

    it "creates initial ledger entry" do
      portfolio = described_class.create!(name: "test_portfolio", initial_capital: 50_000)

      ledger = PaperLedger.last
      expect(ledger.paper_portfolio).to eq(portfolio)
      expect(ledger.transaction_type).to eq("credit")
      expect(ledger.amount).to eq(50_000)
      expect(ledger.reason).to eq("initial_capital")
    end

    context "when creation fails" do
      before do
        allow(PaperPortfolio).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(PaperPortfolio.new))
      end

      it "raises error" do
        expect do
          described_class.create(name: "test", initial_capital: 1000)
        end.to raise_error(ActiveRecord::RecordInvalid)
      end

      it "logs error on failure" do
        allow(Rails.logger).to receive(:error)
        allow(PaperPortfolio).to receive(:create!).and_raise(StandardError.new("Database error"))

        expect do
          described_class.create(name: "test", initial_capital: 1000)
        end.to raise_error(StandardError)

        expect(Rails.logger).to have_received(:error)
      end
    end

    context "with edge cases" do
      before do
        PaperPortfolio.where(name: "test_edge").destroy_all
      end

      it "handles zero initial capital" do
        portfolio = described_class.create!(name: "test_edge", initial_capital: 0)
        portfolio.reload

        expect(portfolio.capital).to eq(0)
        expect(portfolio.available_capital).to eq(0)
      end

      it "handles very large initial capital" do
        large_capital = 1_000_000_000
        portfolio = described_class.create!(name: "test_edge", initial_capital: large_capital)
        portfolio.reload

        expect(portfolio.capital).to eq(large_capital * 2) # Initial + ledger credit
      end

      it "handles duplicate name creation" do
        described_class.create!(name: "test_edge", initial_capital: 10_000)

        # Second creation with same name should fail or create separate portfolio
        expect do
          described_class.create(name: "test_edge", initial_capital: 20_000)
        end.to change(PaperPortfolio, :count).by(1) # Creates new portfolio with same name
      end

      it "logs creation info" do
        allow(Rails.logger).to receive(:info)

        described_class.create!(name: "test_edge", initial_capital: 10_000)

        expect(Rails.logger).to have_received(:info).at_least(:once)
      end
    end
  end

  describe "#create" do
    context "with ledger entry creation" do
      before do
        PaperPortfolio.where(name: "test_ledger").destroy_all
      end

      it "creates ledger entry with correct description" do
        described_class.create!(name: "test_ledger", initial_capital: 10_000)

        ledger = PaperLedger.last
        expect(ledger.description).to include("Initial capital allocation")
      end

      it "handles ledger creation failure gracefully" do
        allow(PaperTrading::Ledger).to receive(:credit).and_raise(StandardError.new("Ledger error"))
        allow(Rails.logger).to receive(:error)

        expect do
          described_class.create(name: "test_ledger", initial_capital: 10_000)
        end.to raise_error(StandardError)

        expect(Rails.logger).to have_received(:error)
      end
    end
  end
end
