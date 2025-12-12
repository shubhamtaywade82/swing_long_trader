# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtesting::Config, type: :service do
  describe '.from_hash' do
    it 'creates config from hash' do
      hash = {
        initial_capital: 200_000,
        risk_per_trade: 3.0,
        commission_rate: 0.1,
        slippage_pct: 0.05
      }

      config = described_class.from_hash(hash)

      expect(config.initial_capital).to eq(200_000)
      expect(config.risk_per_trade).to eq(3.0)
      expect(config.commission_rate).to eq(0.1)
      expect(config.slippage_pct).to eq(0.05)
    end
  end

  describe '#initialize' do
    context 'with default values' do
      it 'uses default values' do
        config = described_class.new

        expect(config.initial_capital).to eq(100_000.0)
        expect(config.risk_per_trade).to eq(2.0)
        expect(config.commission_rate).to eq(0.0)
        expect(config.slippage_pct).to eq(0.0)
      end
    end

    context 'with custom values' do
      it 'uses provided values' do
        config = described_class.new(
          initial_capital: 150_000,
          risk_per_trade: 2.5,
          commission_rate: 0.05,
          slippage_pct: 0.1
        )

        expect(config.initial_capital).to eq(150_000)
        expect(config.risk_per_trade).to eq(2.5)
        expect(config.commission_rate).to eq(0.05)
        expect(config.slippage_pct).to eq(0.1)
      end
    end
  end

  describe '#to_hash' do
    it 'converts config to hash' do
      config = described_class.new(
        initial_capital: 200_000,
        risk_per_trade: 3.0
      )

      hash = config.to_hash

      expect(hash[:initial_capital]).to eq(200_000)
      expect(hash[:risk_per_trade]).to eq(3.0)
    end
  end

  describe '#from_date' do
    context 'when date_range is provided' do
      it 'returns from_date from date_range' do
        config = described_class.new(
          date_range: { from_date: 1.year.ago.to_date, to_date: Date.today }
        )

        expect(config.from_date).to eq(1.year.ago.to_date)
      end
    end

    context 'when date_range is not provided' do
      it 'returns default from_date' do
        config = described_class.new

        expect(config.from_date).to eq(Date.today - 1.year)
      end
    end
  end

  describe '#to_date' do
    context 'when date_range is provided' do
      it 'returns to_date from date_range' do
        config = described_class.new(
          date_range: { from_date: 1.year.ago.to_date, to_date: Date.today }
        )

        expect(config.to_date).to eq(Date.today)
      end
    end

    context 'when date_range is not provided' do
      it 'returns default to_date' do
        config = described_class.new

        expect(config.to_date).to eq(Date.today)
      end
    end
  end

  describe '#risk_amount_per_trade' do
    it 'calculates risk amount correctly' do
      config = described_class.new(
        initial_capital: 100_000,
        risk_per_trade: 2.0
      )

      expect(config.risk_amount_per_trade).to eq(2000.0)
    end
  end

  describe '#apply_slippage' do
    context 'when slippage is zero' do
      it 'returns original price' do
        config = described_class.new(slippage_pct: 0.0)

        expect(config.apply_slippage(100.0, :long)).to eq(100.0)
      end
    end

    context 'when direction is long' do
      it 'adds slippage to price' do
        config = described_class.new(slippage_pct: 0.1)

        expect(config.apply_slippage(100.0, :long)).to eq(100.1)
      end
    end

    context 'when direction is short' do
      it 'subtracts slippage from price' do
        config = described_class.new(slippage_pct: 0.1)

        expect(config.apply_slippage(100.0, :short)).to eq(99.9)
      end
    end
  end

  describe '#apply_commission' do
    context 'when commission is zero' do
      it 'returns original amount' do
        config = described_class.new(commission_rate: 0.0)

        expect(config.apply_commission(1000.0)).to eq(1000.0)
      end
    end

    context 'when commission is non-zero' do
      it 'adds commission to amount' do
        config = described_class.new(commission_rate: 0.1)

        expect(config.apply_commission(1000.0)).to eq(1000.1)
      end
    end
  end

  describe '#validate!' do
    context 'when config is valid' do
      it 'returns true' do
        config = described_class.new(
          initial_capital: 100_000,
          risk_per_trade: 2.0,
          date_range: { from_date: 1.year.ago.to_date, to_date: Date.today }
        )

        expect(config.validate!).to be true
      end
    end

    context 'when initial_capital is invalid' do
      it 'raises error' do
        config = described_class.new(initial_capital: -1000)

        expect { config.validate! }.to raise_error(ArgumentError, /Initial capital must be positive/)
      end
    end

    context 'when risk_per_trade is invalid' do
      it 'raises error for too low risk' do
        config = described_class.new(risk_per_trade: 0.05)

        expect { config.validate! }.to raise_error(ArgumentError, /Risk per trade/)
      end

      it 'raises error for too high risk' do
        config = described_class.new(risk_per_trade: 15.0)

        expect { config.validate! }.to raise_error(ArgumentError, /Risk per trade/)
      end
    end

    context 'when date_range is invalid' do
      it 'raises error' do
        config = described_class.new(
          date_range: { from_date: Date.today, to_date: 1.year.ago.to_date }
        )

        expect { config.validate! }.to raise_error(ArgumentError, /Invalid date range/)
      end
    end
  end
end

