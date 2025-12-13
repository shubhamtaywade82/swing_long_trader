FactoryBot.define do
  factory :screener_result do
    screener_type { "MyString" }
    instrument { nil }
    symbol { "MyString" }
    score { "9.99" }
    base_score { "9.99" }
    mtf_score { "9.99" }
    indicators { "MyText" }
    metadata { "MyText" }
    multi_timeframe { "MyText" }
    analyzed_at { "2025-12-14 00:30:44" }
  end
end
