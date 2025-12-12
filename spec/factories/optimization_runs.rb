# frozen_string_literal: true

FactoryBot.define do
  factory :optimization_run do
    start_date { 3.months.ago.to_date }
    end_date { Date.today }
    strategy_type { 'swing' }
    initial_capital { 100_000.0 }
    optimization_metric { 'sharpe_ratio' }
    status { 'completed' }
    parameter_ranges { { risk_per_trade: [1, 5] }.to_json }
    best_parameters { { risk_per_trade: 3 }.to_json }
    best_metrics { { sharpe_ratio: 1.5 }.to_json }
    all_results { [{ score: 1.5, risk_per_trade: 3 }].to_json }
    sensitivity_analysis { nil }

    trait :long_term do
      strategy_type { 'long_term' }
    end

    trait :pending do
      status { 'pending' }
    end

    trait :running do
      status { 'running' }
    end

    trait :failed do
      status { 'failed' }
    end
  end
end

