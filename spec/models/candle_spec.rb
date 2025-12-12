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

  describe 'edge cases' do
    it 'handles zero volume' do
      candle = Candle.new(
        timestamp: Time.current,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        close: 103.0,
        volume: 0
      )

      expect(candle.volume).to eq(0)
    end

    it 'handles negative prices' do
      candle = Candle.new(
        timestamp: Time.current,
        open: -100.0,
        high: -95.0,
        low: -105.0,
        close: -98.0,
        volume: 1_000_000
      )

      expect(candle.open).to eq(-100.0)
      expect(candle.close).to eq(-98.0)
    end

    it 'handles very large numbers' do
      candle = Candle.new(
        timestamp: Time.current,
        open: 1_000_000.0,
        high: 1_000_500.0,
        low: 999_500.0,
        close: 1_000_300.0,
        volume: 1_000_000_000
      )

      expect(candle.open).to eq(1_000_000.0)
      expect(candle.volume).to eq(1_000_000_000)
    end

    it 'handles decimal volume conversion' do
      candle = Candle.new(
        timestamp: Time.current,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        close: 103.0,
        volume: 1_000_000.5
      )

      expect(candle.volume).to eq(1_000_000) # Converted to integer
    end

    it 'handles nil timestamp' do
      candle = Candle.new(
        timestamp: nil,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        close: 103.0,
        volume: 1_000_000
      )

      expect(candle.timestamp).to be_nil
    end

    it 'handles bullish? with very small difference' do
      candle = Candle.new(
        timestamp: Time.current,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        close: 100.0001,
        volume: 1_000_000
      )

      expect(candle.bullish?).to be true
    end

    it 'handles bearish? with very small difference' do
      candle = Candle.new(
        timestamp: Time.current,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        close: 99.9999,
        volume: 1_000_000
      )

      expect(candle.bearish?).to be true
    end

    it 'handles bullish? and bearish? being mutually exclusive' do
      candle = Candle.new(
        timestamp: Time.current,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        close: 103.0,
        volume: 1_000_000
      )

      expect(candle.bullish?).not_to eq(candle.bearish?)
    end
  end
end

