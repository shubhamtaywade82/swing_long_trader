# frozen_string_literal: true

FactoryBot.define do
  factory :candle do
    timestamp { 1.day.ago }
    open { 100.0 }
    high { 105.0 }
    low { 99.0 }
    close { 103.0 }
    volume { 1_000_000 }

    # Candle is a plain Ruby class, not ActiveRecord
    # Use build strategy (not create) since there's no database persistence
    to_create { |instance| instance }

    initialize_with { Candle.new(**attributes) }
  end
end

