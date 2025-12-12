# frozen_string_literal: true

FactoryBot.define do
  factory :instrument do
    sequence(:security_id) { |n| "SEC#{n}" }
    sequence(:symbol_name) { |n| "STOCK#{n}" }
    exchange { "NSE" }
    segment { "E" }
    instrument_type { "EQUITY" }
    display_name { symbol_name }
    lot_size { 1 }
    tick_size { 0.05 }
  end

  factory :index_instrument, parent: :instrument do
    segment { "I" }
    instrument_type { "INDEX" }
    symbol_name { "NIFTY" }
  end
end
