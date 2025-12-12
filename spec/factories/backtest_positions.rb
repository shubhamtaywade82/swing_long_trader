# frozen_string_literal: true

FactoryBot.define do
  factory :backtest_position do
    backtest_run
    instrument
    entry_date { 1.month.ago }
    exit_date { 2.weeks.ago }
    direction { "long" }
    entry_price { 100.0 }
    exit_price { 110.0 }
    quantity { 100 }
    stop_loss { 95.0 }
    take_profit { 115.0 }
    pnl { 1000.0 }
    pnl_pct { 10.0 }
    holding_days { 14 }
    exit_reason { "take_profit" }

    trait :short do
      direction { "short" }
      entry_price { 100.0 }
      exit_price { 90.0 }
      pnl { 1000.0 }
      pnl_pct { 10.0 }
    end

    trait :open do
      exit_date { nil }
      exit_price { nil }
      pnl { nil }
      pnl_pct { nil }
      exit_reason { nil }
    end

    trait :stop_loss_exit do
      exit_reason { "stop_loss" }
      exit_price { 95.0 }
      pnl { -500.0 }
      pnl_pct { -5.0 }
    end
  end
end
