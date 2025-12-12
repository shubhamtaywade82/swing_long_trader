# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::BaseIndicator, type: :service do
  let(:series) { CandleSeries.new(symbol: 'TEST', interval: '1D') }
  let(:config) { {} }

  before do
    50.times { series.add_candle(create(:candle)) }
  end

  describe '#initialize' do
    it 'initializes with series and config' do
      indicator = described_class.new(series: series, config: config)

      expect(indicator.series).to eq(series)
      expect(indicator.config).to eq(config)
    end
  end

  describe '#calculate_at' do
    it 'raises NotImplementedError' do
      indicator = described_class.new(series: series, config: config)

      expect { indicator.calculate_at(0) }.to raise_error(NotImplementedError)
    end
  end

  describe '#ready?' do
    it 'raises NotImplementedError' do
      indicator = described_class.new(series: series, config: config)

      expect { indicator.ready?(0) }.to raise_error(NotImplementedError)
    end
  end

  describe '#min_required_candles' do
    it 'raises NotImplementedError' do
      indicator = described_class.new(series: series, config: config)

      expect { indicator.min_required_candles }.to raise_error(NotImplementedError)
    end
  end

  describe '#name' do
    it 'returns snake_case name' do
      indicator = described_class.new(series: series, config: config)

      expect(indicator.name).to eq('base_indicator')
    end
  end
end

