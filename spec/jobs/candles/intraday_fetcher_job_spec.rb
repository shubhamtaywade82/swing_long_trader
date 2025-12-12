# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::IntradayFetcherJob, type: :job do
  let(:instrument) { create(:instrument) }

  describe '#perform' do
    context 'when instrument_ids are provided' do
      before do
        allow(Candles::IntradayFetcher).to receive(:call).and_return(
          create(:candle_series, candles: create_list(:candle, 10))
        )
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'fetches candles for specified instruments' do
        result = described_class.new.perform(instrument_ids: [instrument.id], interval: '15')

        expect(result[:processed]).to eq(1)
        expect(result[:success]).to eq(1)
        expect(Candles::IntradayFetcher).to have_received(:call).with(
          instrument: instrument,
          interval: '15'
        )
      end
    end

    context 'when no instrument_ids provided' do
      before do
        allow_any_instance_of(described_class).to receive(:get_top_candidates).and_return(
          Instrument.where(id: instrument.id)
        )
        allow(Candles::IntradayFetcher).to receive(:call).and_return(
          create(:candle_series, candles: create_list(:candle, 10))
        )
      end

      it 'uses top candidates' do
        result = described_class.new.perform(interval: '15')

        expect(result[:processed]).to eq(1)
      end
    end

    context 'when fetcher returns no candles' do
      before do
        allow(Candles::IntradayFetcher).to receive(:call).and_return(nil)
      end

      it 'records as failed' do
        result = described_class.new.perform(instrument_ids: [instrument.id], interval: '15')

        expect(result[:failed]).to eq(1)
        expect(result[:errors].first[:error]).to eq('No candles returned')
      end
    end

    context 'when fetcher raises error' do
      before do
        allow(Candles::IntradayFetcher).to receive(:call).and_raise(StandardError, 'API error')
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'handles error gracefully' do
        result = described_class.new.perform(instrument_ids: [instrument.id], interval: '15')

        expect(result[:failed]).to eq(1)
        expect(result[:errors].first[:error]).to eq('API error')
      end
    end

    context 'when job fails completely' do
      before do
        allow(Candles::IntradayFetcher).to receive(:call).and_raise(StandardError, 'Critical error')
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'sends error alert and raises' do
        expect do
          described_class.new.perform(instrument_ids: [instrument.id], interval: '15')
        end.to raise_error(StandardError, 'Critical error')

        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end
    end
  end
end

