# frozen_string_literal: true

FactoryBot.define do
  factory :setting do
    key { "test_key_#{SecureRandom.hex(4)}" }
    value { "test_value" }

    trait :with_json_value do
      value { { key: "value" }.to_json }
    end

    trait :with_numeric_value do
      value { "123.45" }
    end
  end
end
