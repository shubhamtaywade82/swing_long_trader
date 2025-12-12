# frozen_string_literal: true

require "rails_helper"

RSpec.describe BacktestRun do
  describe "validations" do
    it "is valid with valid attributes" do
      run = build(:backtest_run)
      expect(run).to be_valid
    end

    it "requires start_date" do
      run = build(:backtest_run, start_date: nil)
      expect(run).not_to be_valid
      expect(run.errors[:start_date]).to include("can't be blank")
    end

    it "requires end_date" do
      run = build(:backtest_run, end_date: nil)
      expect(run).not_to be_valid
      expect(run.errors[:end_date]).to include("can't be blank")
    end

    it "requires strategy_type" do
      run = build(:backtest_run, strategy_type: nil)
      expect(run).not_to be_valid
      expect(run.errors[:strategy_type]).to include("can't be blank")
    end

    it "requires initial_capital" do
      run = build(:backtest_run, initial_capital: nil)
      expect(run).not_to be_valid
      expect(run.errors[:initial_capital]).to include("can't be blank")
    end

    it "requires risk_per_trade" do
      run = build(:backtest_run, risk_per_trade: nil)
      expect(run).not_to be_valid
      expect(run.errors[:risk_per_trade]).to include("can't be blank")
    end

    it "validates strategy_type inclusion" do
      run = build(:backtest_run, strategy_type: "invalid")
      expect(run).not_to be_valid
      expect(run.errors[:strategy_type]).to include("is not included in the list")
    end

    it "validates status inclusion" do
      run = build(:backtest_run, status: "invalid")
      expect(run).not_to be_valid
      expect(run.errors[:status]).to include("is not included in the list")
    end
  end

  describe "associations" do
    it "has many backtest_positions" do
      run = create(:backtest_run)
      create_list(:backtest_position, 3, backtest_run: run)
      expect(run.backtest_positions.count).to eq(3)
    end
  end

  describe "scopes" do
    it "completed scope returns completed runs" do
      completed = create(:backtest_run, status: "completed")
      pending = create(:backtest_run, status: "pending")
      running = create(:backtest_run, status: "running")

      completed_runs = described_class.completed
      expect(completed_runs).to include(completed)
      expect(completed_runs).not_to include(pending)
      expect(completed_runs).not_to include(running)
    end

    it "swing scope returns swing runs" do
      swing = create(:backtest_run, strategy_type: "swing")
      long_term = create(:backtest_run, strategy_type: "long_term")

      swing_runs = described_class.swing
      expect(swing_runs).to include(swing)
      expect(swing_runs).not_to include(long_term)
    end

    it "long_term scope returns long_term runs" do
      swing = create(:backtest_run, strategy_type: "swing")
      long_term = create(:backtest_run, strategy_type: "long_term")

      long_term_runs = described_class.long_term
      expect(long_term_runs).to include(long_term)
      expect(long_term_runs).not_to include(swing)
    end
  end

  describe "#config_hash" do
    it "parses JSON config" do
      config = { initial_capital: 100_000, risk_per_trade: 2.0 }
      run = create(:backtest_run, config: config.to_json)

      # JSON.parse returns string keys
      expect(run.config_hash).to eq(config.stringify_keys)
    end

    it "returns empty hash for blank config" do
      run = create(:backtest_run, config: nil)
      expect(run.config_hash).to eq({})

      run.config = ""
      expect(run.config_hash).to eq({})
    end

    it "handles invalid JSON gracefully" do
      run = create(:backtest_run, config: "invalid json")
      expect(run.config_hash).to eq({})
    end
  end

  describe "#results_hash" do
    it "parses JSON results" do
      results = { total_return: 15.5, win_rate: 55.0 }
      run = create(:backtest_run, results: results.to_json)

      # JSON.parse returns string keys
      expect(run.results_hash).to eq(results.stringify_keys)
    end

    it "returns empty hash for blank results" do
      run = create(:backtest_run, results: nil)
      expect(run.results_hash).to eq({})

      run.results = ""
      expect(run.results_hash).to eq({})
    end

    it "handles invalid JSON gracefully" do
      run = create(:backtest_run, results: "invalid json")
      expect(run.results_hash).to eq({})
    end
  end

  describe "edge cases" do
    it "handles config_hash with empty string" do
      run = create(:backtest_run, config: "")
      expect(run.config_hash).to eq({})
    end

    it "handles results_hash with empty string" do
      run = create(:backtest_run, results: "")
      expect(run.results_hash).to eq({})
    end

    it "handles config_hash with complex nested JSON" do
      config = {
        initial_capital: 100_000,
        risk_per_trade: 2.0,
        strategy: {
          entry_conditions: { min_score: 80 },
          exit_conditions: { profit_target: 30.0 },
        },
      }
      run = create(:backtest_run, config: config.to_json)
      expect(run.config_hash).to have_key("strategy")
    end

    it "handles results_hash with complex nested JSON" do
      results = {
        total_return: 15.5,
        metrics: {
          sharpe_ratio: 1.5,
          max_drawdown: 5.0,
        },
      }
      run = create(:backtest_run, results: results.to_json)
      expect(run.results_hash).to have_key("metrics")
    end

    it "handles status values correctly" do
      %w[pending running completed failed].each do |status|
        run = create(:backtest_run, status: status)
        expect(run).to be_valid
      end
    end

    it "handles strategy_type values correctly" do
      %w[swing long_term].each do |strategy_type|
        run = create(:backtest_run, strategy_type: strategy_type)
        expect(run).to be_valid
      end
    end

    it "handles zero initial_capital" do
      run = build(:backtest_run, initial_capital: 0)
      expect(run).to be_valid
    end

    it "handles zero risk_per_trade" do
      run = build(:backtest_run, risk_per_trade: 0)
      expect(run).to be_valid
    end

    it "handles negative initial_capital" do
      run = build(:backtest_run, initial_capital: -1000)
      # Depending on validation, this might be valid or invalid
      # Test that it doesn't crash
      expect(run.initial_capital).to eq(-1000)
    end

    it "handles negative risk_per_trade" do
      run = build(:backtest_run, risk_per_trade: -1.0)
      # Depending on validation, this might be valid or invalid
      # Test that it doesn't crash
      expect(run.risk_per_trade).to eq(-1.0)
    end
  end
end
