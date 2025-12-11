# frozen_string_literal: true

FactoryBot.define do
  factory :backtest_run do
    start_date { 3.months.ago.to_date }
    end_date { Date.today }
    strategy_type { 'swing' }
    initial_capital { 100_000.0 }
    risk_per_trade { 2.0 }
    status { 'completed' }
    total_return { 15.5 }
    annualized_return { 6.2 }
    max_drawdown { 8.3 }
    sharpe_ratio { 1.2 }
    sortino_ratio { 1.5 }
    win_rate { 55.0 }
    total_trades { 100 }
    config { { initial_capital: 100_000, risk_per_trade: 2.0 }.to_json }
    results { { total_return: 15.5, win_rate: 55.0 }.to_json }

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

