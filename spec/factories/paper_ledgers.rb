# frozen_string_literal: true

FactoryBot.define do
  factory :paper_ledger do
    paper_portfolio
    paper_position { nil }
    amount { 1000.0 }
    transaction_type { "credit" }
    reason { "Test transaction" }
    meta { nil }

    trait :debit do
      transaction_type { "debit" }
    end

    trait :with_position do
      paper_position
    end
  end
end
