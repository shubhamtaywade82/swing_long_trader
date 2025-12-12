# frozen_string_literal: true

FactoryBot.define do
  factory :paper_portfolio do
    sequence(:name) { |n| "Test Portfolio #{n}" }
    capital { 100_000.0 }
    total_equity { 100_000.0 }
    available_capital { 100_000.0 }
    pnl_unrealized { 0.0 }
    reserved_capital { 0.0 }
    peak_equity { 100_000.0 }
    max_drawdown { 0.0 }
    metadata { nil }
  end
end
