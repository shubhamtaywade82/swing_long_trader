# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperPortfolio do
  let(:portfolio) { create(:paper_portfolio, name: "Test Portfolio", capital: 100_000) }

  describe "validations" do
    it "requires name" do
      portfolio = described_class.new(capital: 100_000)
      expect(portfolio).not_to be_valid
      expect(portfolio.errors[:name]).to include("can't be blank")
    end

    it "requires capital to be present (not nil)" do
      portfolio = described_class.new(name: "Test", capital: nil)
      expect(portfolio).not_to be_valid
      expect(portfolio.errors[:capital]).to include("can't be blank")
    end

    it "requires capital to be >= 0" do
      portfolio = described_class.new(name: "Test", capital: -100)
      expect(portfolio).not_to be_valid
      expect(portfolio.errors[:capital]).to be_present
    end

    it "allows capital to be 0" do
      portfolio = described_class.new(name: "Test", capital: 0)
      expect(portfolio).to be_valid
    end

    it "allows capital to be positive" do
      portfolio = described_class.new(name: "Test", capital: 100_000)
      expect(portfolio).to be_valid
    end

    it "requires unique name (case insensitive)" do
      create(:paper_portfolio, name: "Test Portfolio")
      duplicate = described_class.new(name: "test portfolio", capital: 100_000)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end
  end

  describe "associations" do
    it "has many paper_positions" do
      position = create(:paper_position, paper_portfolio: portfolio)
      expect(portfolio.paper_positions).to include(position)
    end

    it "has many paper_ledgers" do
      ledger = create(:paper_ledger, paper_portfolio: portfolio)
      expect(portfolio.paper_ledgers).to include(ledger)
    end
  end

  describe "#metadata_hash" do
    it "returns parsed JSON metadata" do
      portfolio.update!(metadata: '{"key": "value"}')
      expect(portfolio.metadata_hash).to eq({ "key" => "value" })
    end

    it "returns empty hash for blank metadata" do
      expect(portfolio.metadata_hash).to eq({})
    end

    it "returns empty hash for invalid JSON" do
      portfolio.update!(metadata: "invalid json")
      expect(portfolio.metadata_hash).to eq({})
    end
  end

  describe "#update_equity!" do
    it "updates total_equity and available_capital" do
      portfolio.update!(capital: 100_000, pnl_unrealized: 5_000, reserved_capital: 10_000)
      portfolio.update_equity!

      expect(portfolio.total_equity).to eq(105_000)
      expect(portfolio.available_capital).to eq(90_000)
    end
  end

  describe "#update_drawdown!" do
    it "updates max_drawdown and peak_equity" do
      portfolio.update!(peak_equity: 110_000, total_equity: 100_000)
      portfolio.update_drawdown!

      expect(portfolio.max_drawdown).to be > 0
      expect(portfolio.peak_equity).to eq(110_000)
    end

    it "does nothing if peak_equity is zero" do
      portfolio.update!(peak_equity: 0, total_equity: 100_000)
      expect { portfolio.update_drawdown! }.not_to(change(portfolio, :max_drawdown))
    end
  end

  describe "#open_positions" do
    it "returns only open positions" do
      open_pos = create(:paper_position, paper_portfolio: portfolio, status: "open")
      closed_pos = create(:paper_position, paper_portfolio: portfolio, status: "closed")

      expect(portfolio.open_positions).to include(open_pos)
      expect(portfolio.open_positions).not_to include(closed_pos)
    end
  end

  describe "#closed_positions" do
    it "returns only closed positions" do
      open_pos = create(:paper_position, paper_portfolio: portfolio, status: "open")
      closed_pos = create(:paper_position, paper_portfolio: portfolio, status: "closed")

      expect(portfolio.closed_positions).to include(closed_pos)
      expect(portfolio.closed_positions).not_to include(open_pos)
    end
  end

  describe "#total_exposure" do
    it "calculates total exposure from open positions" do
      create(:paper_position, paper_portfolio: portfolio, status: "open", current_price: 100, quantity: 10)
      create(:paper_position, paper_portfolio: portfolio, status: "open", current_price: 50, quantity: 20)
      create(:paper_position, paper_portfolio: portfolio, status: "closed", current_price: 200, quantity: 5)

      expect(portfolio.total_exposure).to eq(2000) # (100 * 10) + (50 * 20)
    end
  end

  describe "#utilization_pct" do
    it "calculates utilization percentage" do
      portfolio.update!(capital: 100_000)
      create(:paper_position, paper_portfolio: portfolio, status: "open", current_price: 100, quantity: 50)

      expect(portfolio.utilization_pct).to eq(5.0) # (100 * 50) / 100_000 * 100
    end

    it "returns 0 if capital is zero" do
      portfolio.update!(capital: 0)
      expect(portfolio.utilization_pct).to eq(0)
    end

    it "returns 0 if no open positions" do
      portfolio.update!(capital: 100_000)
      expect(portfolio.utilization_pct).to eq(0)
    end
  end

  describe "scopes" do
    it "filters active portfolios" do
      active = create(:paper_portfolio, name: "Active")
      expect(described_class.active).to include(active)
    end
  end

  describe "#update_drawdown!" do
    context "when peak_equity increases" do
      it "updates peak_equity to new high" do
        portfolio.update!(peak_equity: 100_000, total_equity: 110_000)
        portfolio.update_drawdown!

        expect(portfolio.peak_equity).to eq(110_000)
        expect(portfolio.max_drawdown).to eq(0)
      end
    end

    context "when equity decreases from peak" do
      it "calculates drawdown percentage" do
        portfolio.update!(peak_equity: 110_000, total_equity: 100_000, max_drawdown: 0)
        portfolio.update_drawdown!

        expect(portfolio.max_drawdown).to be_within(0.01).of(9.09) # (110_000 - 100_000) / 110_000 * 100
        expect(portfolio.peak_equity).to eq(110_000)
      end
    end

    context "when equity equals peak" do
      it "does not change max_drawdown" do
        portfolio.update!(peak_equity: 100_000, total_equity: 100_000, max_drawdown: 5.0)
        portfolio.update_drawdown!

        expect(portfolio.max_drawdown).to eq(5.0)
        expect(portfolio.peak_equity).to eq(100_000)
      end
    end
  end

  describe "#total_exposure" do
    it "returns 0 if no open positions" do
      expect(portfolio.total_exposure).to eq(0)
    end

    it "calculates exposure correctly with multiple positions" do
      create(:paper_position, paper_portfolio: portfolio, status: "open", current_price: 100, quantity: 10)
      create(:paper_position, paper_portfolio: portfolio, status: "open", current_price: 50, quantity: 20)
      expect(portfolio.total_exposure).to eq(2000) # (100 * 10) + (50 * 20)
    end
  end

  describe "edge cases" do
    it "handles update_equity! with zero capital" do
      portfolio.update!(capital: 0, pnl_unrealized: 5_000, reserved_capital: 0)
      portfolio.update_equity!

      expect(portfolio.total_equity).to eq(5_000)
      expect(portfolio.available_capital).to eq(0)
    end

    it "handles update_equity! with negative unrealized P&L" do
      portfolio.update!(capital: 100_000, pnl_unrealized: -5_000, reserved_capital: 10_000)
      portfolio.update_equity!

      expect(portfolio.total_equity).to eq(95_000)
      expect(portfolio.available_capital).to eq(90_000)
    end

    it "handles update_equity! with zero reserved_capital" do
      portfolio.update!(capital: 100_000, pnl_unrealized: 5_000, reserved_capital: 0)
      portfolio.update_equity!

      expect(portfolio.total_equity).to eq(105_000)
      expect(portfolio.available_capital).to eq(100_000)
    end

    it "handles update_drawdown! with zero total_equity" do
      portfolio.update!(peak_equity: 100_000, total_equity: 0)
      portfolio.update_drawdown!

      expect(portfolio.max_drawdown).to eq(100.0) # 100% drawdown
      expect(portfolio.peak_equity).to eq(100_000)
    end

    it "handles update_drawdown! when max_drawdown already exists" do
      portfolio.update!(peak_equity: 110_000, total_equity: 100_000, max_drawdown: 5.0)
      portfolio.update_drawdown!

      # Should keep the maximum drawdown
      expect(portfolio.max_drawdown).to be >= 5.0
    end

    it "handles total_exposure with zero prices" do
      create(:paper_position, paper_portfolio: portfolio, status: "open", current_price: 0, quantity: 10)
      expect(portfolio.total_exposure).to eq(0)
    end

    it "handles total_exposure with zero quantities" do
      create(:paper_position, paper_portfolio: portfolio, status: "open", current_price: 100, quantity: 0)
      expect(portfolio.total_exposure).to eq(0)
    end

    it "handles utilization_pct with very high exposure" do
      portfolio.update!(capital: 100_000)
      create(:paper_position, paper_portfolio: portfolio, status: "open", current_price: 100, quantity: 1_000)

      expect(portfolio.utilization_pct).to eq(100.0) # 100% utilization
    end

    it "handles utilization_pct with very small capital" do
      portfolio.update!(capital: 1)
      create(:paper_position, paper_portfolio: portfolio, status: "open", current_price: 100, quantity: 1)

      expect(portfolio.utilization_pct).to eq(10_000.0) # >100% utilization
    end

    it "handles metadata_hash with empty string" do
      portfolio.update!(metadata: "")
      expect(portfolio.metadata_hash).to eq({})
    end

    it "handles open_positions with no positions" do
      expect(portfolio.open_positions).to be_empty
    end

    it "handles closed_positions with no positions" do
      expect(portfolio.closed_positions).to be_empty
    end
  end
end
