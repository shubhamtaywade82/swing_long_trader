# frozen_string_literal: true

FactoryBot.define do
  factory :candle_series_record do
    association :instrument
    timeframe { '1D' }
    timestamp { 1.day.ago }
    open { 100.0 }
    high { 105.0 }
    low { 99.0 }
    close { 103.0 }
    volume { 1_000_000 }
  end

  factory :daily_candle, parent: :candle_series_record do
    timeframe { '1D' }
  end

  factory :weekly_candle, parent: :candle_series_record do
    timeframe { '1W' }
    timestamp { 1.week.ago }
  end
end

