# frozen_string_literal: true

FactoryBot.define do
  factory :paper_position do
    paper_portfolio
    instrument
    direction { "long" }
    entry_price { 100.0 }
    current_price { 105.0 }
    quantity { 10 }
    status { "open" }
    opened_at { Time.current }
    pnl { 0.0 }
    pnl_pct { 0.0 }
    sl { nil }
    tp { nil }
    exit_price { nil }
    closed_at { nil }
    metadata { nil }

    trait :short do
      direction { "short" }
    end

    trait :closed do
      status { "closed" }
      exit_price { 110.0 }
      closed_at { Time.current }
    end
  end
end
