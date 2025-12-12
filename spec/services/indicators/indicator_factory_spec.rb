# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::IndicatorFactory, type: :service do
  let(:series) { CandleSeries.new(symbol: 'TEST', interval: '1D') }

  before do
    50.times { series.add_candle(create(:candle)) }
  end

  describe '.build_indicators' do
    context 'when config has indicators' do
      let(:config) do
        {
          indicators: [
            { type: 'rsi', config: { period: 14 } },
            { type: 'adx', config: { period: 14 } }
          ]
        }
      end

      it 'builds multiple indicators' do
        indicators = described_class.build_indicators(series: series, config: config)

        expect(indicators.size).to eq(2)
        expect(indicators.first).to be_a(Indicators::RsiIndicator)
        expect(indicators.last).to be_a(Indicators::AdxIndicator)
      end
    end

    context 'when config has no indicators' do
      let(:config) { {} }

      it 'returns empty array' do
        indicators = described_class.build_indicators(series: series, config: config)

        expect(indicators).to be_empty
      end
    end
  end

  describe '.build_indicator' do
    context 'when type is supertrend' do
      it 'builds SupertrendIndicator' do
        indicator = described_class.build_indicator(
          series: series,
          config: { type: 'supertrend' },
          global_config: {}
        )

        expect(indicator).to be_a(Indicators::SupertrendIndicator)
      end
    end

    context 'when type is rsi' do
      it 'builds RsiIndicator' do
        indicator = described_class.build_indicator(
          series: series,
          config: { type: 'rsi' },
          global_config: {}
        )

        expect(indicator).to be_a(Indicators::RsiIndicator)
      end
    end

    context 'when type is adx' do
      it 'builds AdxIndicator' do
        indicator = described_class.build_indicator(
          series: series,
          config: { type: 'adx' },
          global_config: {}
        )

        expect(indicator).to be_a(Indicators::AdxIndicator)
      end
    end

    context 'when type is macd' do
      it 'builds MacdIndicator' do
        indicator = described_class.build_indicator(
          series: series,
          config: { type: 'macd' },
          global_config: {}
        )

        expect(indicator).to be_a(Indicators::MacdIndicator)
      end
    end

    context 'when type is trend_duration' do
      it 'builds TrendDurationIndicator' do
        indicator = described_class.build_indicator(
          series: series,
          config: { type: 'trend_duration' },
          global_config: {}
        )

        expect(indicator).to be_a(Indicators::TrendDurationIndicator)
      end
    end

    context 'when type is unknown' do
      it 'returns nil and logs warning' do
        allow(Rails.logger).to receive(:warn)

        indicator = described_class.build_indicator(
          series: series,
          config: { type: 'unknown' },
          global_config: {}
        )

        expect(indicator).to be_nil
        expect(Rails.logger).to have_received(:warn)
      end
    end

    context 'when building fails' do
      before do
        allow(Indicators::RsiIndicator).to receive(:new).and_raise(StandardError, 'Error')
        allow(Rails.logger).to receive(:error)
      end

      it 'returns nil and logs error' do
        indicator = described_class.build_indicator(
          series: series,
          config: { type: 'rsi' },
          global_config: {}
        )

        expect(indicator).to be_nil
        expect(Rails.logger).to have_received(:error)
      end
    end
  end
end

