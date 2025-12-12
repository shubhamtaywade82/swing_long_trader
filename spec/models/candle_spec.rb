# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candle, type: :model do
  describe 'initialization' do
    it 'creates a candle with all attributes' do
      candle = Candle.new(
        timestamp: Time.current,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        close: 103.0,
        volume: 1_000_000
      )

      expect(candle.timestamp).to be_a(Time)
      expect(candle.open).to eq(100.0)
      expect(candle.high).to eq(105.0)
      expect(candle.low).to eq(99.0)
      expect(candle.close).to eq(103.0)
      expect(candle.volume).to eq(1_000_000)
    end

    it 'converts values to appropriate types' do
      candle = Candle.new(
        timestamp: Time.current,
        open: '100.5',
        high: '105.5',
        low: '99.5',
        close: '103.5',
        volume: '1000000'
      )

      expect(candle.open).to eq(100.5)
      expect(candle.high).to eq(105.5)
      expect(candle.low).to eq(99.5)
      expect(candle.close).to eq(103.5)
      expect(candle.volume).to eq(1_000_000)
    end
  end

  describe '#bullish?' do
    it 'returns true when close >= open' do
      candle = Candle.new(
        timestamp: Time.current,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        close: 103.0,
        volume: 1_000_000
      )

      expect(candle.bullish?).to be true
    end

    it 'returns true when close equals open' do
      candle = Candle.new(
        timestamp: Time.current,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        close: 100.0,
        volume: 1_000_000
      )

      expect(candle.bullish?).to be true
    end
  end

  describe '#bearish?' do
    it 'returns true when close < open' do
      candle = Candle.new(
        timestamp: Time.current,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        close: 98.0,
        volume: 1_000_000
      )

      expect(candle.bearish?).to be true
    end

    it 'returns false when close >= open' do
      candle = Candle.new(
        timestamp: Time.current,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        close: 100.0,
        volume: 1_000_000
      )

      expect(candle.bearish?).to be false
    end
  end
end

