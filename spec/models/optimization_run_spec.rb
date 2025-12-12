# frozen_string_literal: true

require "rails_helper"

RSpec.describe OptimizationRun do
  let(:run) do
    create(:optimization_run,
           start_date: Time.zone.today - 30.days,
           end_date: Time.zone.today,
           strategy_type: "swing",
           initial_capital: 100_000,
           optimization_metric: "sharpe_ratio",
           status: "completed")
  end

  describe "validations" do
    it "requires start_date, end_date, strategy_type, initial_capital, and optimization_metric" do
      run = described_class.new
      expect(run).not_to be_valid
      expect(run.errors[:start_date]).to be_present
      expect(run.errors[:end_date]).to be_present
      expect(run.errors[:strategy_type]).to be_present
      # initial_capital has a default value, so no error expected
      # optimization_metric has a default value ("sharpe_ratio"), so no error expected
    end

    it "requires strategy_type to be swing or long_term" do
      run = described_class.new(
        start_date: Time.zone.today,
        end_date: Time.zone.today,
        strategy_type: "invalid",
        initial_capital: 100_000,
        optimization_metric: "sharpe_ratio",
      )
      expect(run).not_to be_valid
      expect(run.errors[:strategy_type]).to be_present
    end

    it "requires status to be valid" do
      run = described_class.new(
        start_date: Time.zone.today,
        end_date: Time.zone.today,
        strategy_type: "swing",
        initial_capital: 100_000,
        optimization_metric: "sharpe_ratio",
        status: "invalid",
      )
      expect(run).not_to be_valid
      expect(run.errors[:status]).to be_present
    end
  end

  describe "scopes" do
    it "filters by status" do
      completed = create(:optimization_run, status: "completed")
      pending = create(:optimization_run, status: "pending")

      expect(described_class.completed).to include(completed)
      expect(described_class.completed).not_to include(pending)
    end

    it "filters by strategy_type" do
      swing = create(:optimization_run, strategy_type: "swing")
      long_term = create(:optimization_run, strategy_type: "long_term")

      expect(described_class.swing).to include(swing)
      expect(described_class.swing).not_to include(long_term)
    end
  end

  describe "#parameter_ranges_hash" do
    it "returns parsed JSON" do
      run.update!(parameter_ranges: '{"risk_per_trade": [1, 5]}')
      expect(run.parameter_ranges_hash).to eq({ "risk_per_trade" => [1, 5] })
    end

    it "returns empty hash for blank" do
      run.update!(parameter_ranges: nil)
      expect(run.parameter_ranges_hash).to eq({})
    end
  end

  describe "#best_parameters_hash" do
    it "returns parsed JSON" do
      run.update!(best_parameters: '{"risk_per_trade": 3}')
      expect(run.best_parameters_hash).to eq({ "risk_per_trade" => 3 })
    end
  end

  describe "#best_score" do
    it "returns score from best_metrics_hash" do
      run.update!(best_metrics: '{"sharpe_ratio": 1.5}', optimization_metric: "sharpe_ratio")
      run.reload
      expect(run.best_score).to eq(1.5)
    end

    it "returns 0 if metric not found" do
      run.update!(optimization_metric: "sharpe_ratio", best_metrics: "{}")
      run.reload
      expect(run.best_score).to eq(0)
    end

    it "handles different metric types" do
      run.update!(optimization_metric: "total_return", best_metrics: '{"total_return": 25.5}')
      run.reload
      expect(run.best_score).to eq(25.5)
    end
  end

  describe "#top_n_results" do
    it "returns top N results sorted by score" do
      run.update!(all_results: '[{"score": 1.0}, {"score": 2.0}, {"score": 1.5}]')
      top_2 = run.top_n_results(2)
      expect(top_2.size).to eq(2)
      expect(top_2.first["score"]).to eq(2.0)
      expect(top_2.last["score"]).to eq(1.5)
    end
  end
end
