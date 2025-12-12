# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstrumentHelpers, type: :concern do
  let(:instrument) { create(:instrument) }

  describe '#ltp' do
    context 'when API call succeeds' do
      before do
        allow(instrument).to receive(:fetch_ltp_from_api).and_return(100.0)
      end

      it 'returns LTP from API' do
        expect(instrument.ltp).to eq(100.0)
      end
    end

    context 'when API call fails with rate limit' do
      before do
        allow(instrument).to receive(:fetch_ltp_from_api).and_raise(StandardError, '429 rate limit')
        allow(Rails.logger).to receive(:error)
      end

      it 'returns nil without logging error' do
        expect(instrument.ltp).to be_nil
        expect(Rails.logger).not_to have_received(:error)
      end
    end

    context 'when API call fails with other error' do
      before do
        allow(instrument).to receive(:fetch_ltp_from_api).and_raise(StandardError, 'API error')
        allow(Rails.logger).to receive(:error)
      end

      it 'returns nil and logs error' do
        expect(instrument.ltp).to be_nil
        expect(Rails.logger).to have_received(:error)
      end
    end
  end

  describe '#latest_ltp' do
    context 'when quote_ltp exists' do
      before do
        allow(instrument).to receive(:quote_ltp).and_return(100.0)
      end

      it 'returns quote_ltp as BigDecimal' do
        result = instrument.latest_ltp

        expect(result).to be_a(BigDecimal)
        expect(result.to_f).to eq(100.0)
      end
    end

    context 'when quote_ltp is nil' do
      before do
        allow(instrument).to receive(:quote_ltp).and_return(nil)
        allow(instrument).to receive(:fetch_ltp_from_api).and_return(100.0)
      end

      it 'falls back to API' do
        result = instrument.latest_ltp

        expect(result).to be_a(BigDecimal)
        expect(result.to_f).to eq(100.0)
      end
    end
  end

  describe '#resolve_ltp' do
    context 'when meta has LTP' do
      it 'returns LTP from meta' do
        result = instrument.resolve_ltp(
          segment: 'NSE_EQ',
          security_id: instrument.security_id,
          meta: { ltp: 100.0 }
        )

        expect(result).to be_a(BigDecimal)
        expect(result.to_f).to eq(100.0)
      end
    end

    context 'when meta has no LTP' do
      before do
        allow(instrument).to receive(:fetch_ltp_from_api_for_segment).and_return(100.0)
      end

      it 'falls back to API' do
        result = instrument.resolve_ltp(
          segment: 'NSE_EQ',
          security_id: instrument.security_id,
          meta: {}
        )

        expect(result).to be_a(BigDecimal)
        expect(result.to_f).to eq(100.0)
      end
    end

    context 'when API call fails' do
      before do
        allow(instrument).to receive(:fetch_ltp_from_api_for_segment).and_raise(StandardError, 'API error')
        allow(Rails.logger).to receive(:error)
      end

      it 'returns nil and logs error' do
        result = instrument.resolve_ltp(
          segment: 'NSE_EQ',
          security_id: instrument.security_id,
          meta: {}
        )

        expect(result).to be_nil
        expect(Rails.logger).to have_received(:error)
      end
    end
  end

  describe 'enum methods' do
    it 'has exchange enum' do
      expect(instrument).to respond_to(:nse?)
      expect(instrument).to respond_to(:bse?)
    end

    it 'has segment enum with prefix' do
      expect(instrument).to respond_to(:segment_index?)
      expect(instrument).to respond_to(:segment_equity?)
    end

    it 'has instrument_code enum with prefix' do
      expect(instrument).to respond_to(:instrument_code_equity?)
      expect(instrument).to respond_to(:instrument_code_index?)
    end
  end

  describe '#fetch_ltp_from_api_for_segment' do
    let(:success_response) do
      {
        'status' => 'success',
        'data' => {
          'NSE_EQ' => {
            instrument.security_id => { 'last_price' => 100.0 }
          }
        }
      }
    end

    before do
      allow(DhanHQ::Models::MarketFeed).to receive(:ltp).and_return(success_response)
    end

    it 'fetches LTP from API' do
      result = instrument.fetch_ltp_from_api_for_segment(
        segment: 'NSE_EQ',
        security_id: instrument.security_id
      )

      expect(result).to eq(100.0)
    end

    it 'handles API failure' do
      allow(DhanHQ::Models::MarketFeed).to receive(:ltp).and_raise(StandardError, 'API error')
      allow(Rails.logger).to receive(:error)

      result = instrument.fetch_ltp_from_api_for_segment(
        segment: 'NSE_EQ',
        security_id: instrument.security_id
      )

      expect(result).to be_nil
      expect(Rails.logger).to have_received(:error)
    end

    it 'handles rate limit errors without logging' do
      allow(DhanHQ::Models::MarketFeed).to receive(:ltp).and_raise(StandardError, '429 rate limit')
      allow(Rails.logger).to receive(:error)

      result = instrument.fetch_ltp_from_api_for_segment(
        segment: 'NSE_EQ',
        security_id: instrument.security_id
      )

      expect(result).to be_nil
      expect(Rails.logger).not_to have_received(:error)
    end

    it 'handles unsuccessful API response' do
      allow(DhanHQ::Models::MarketFeed).to receive(:ltp).and_return({ 'status' => 'error' })

      result = instrument.fetch_ltp_from_api_for_segment(
        segment: 'NSE_EQ',
        security_id: instrument.security_id
      )

      expect(result).to be_nil
    end

    it 'handles missing data in response' do
      allow(DhanHQ::Models::MarketFeed).to receive(:ltp).and_return({
        'status' => 'success',
        'data' => {}
      })

      result = instrument.fetch_ltp_from_api_for_segment(
        segment: 'NSE_EQ',
        security_id: instrument.security_id
      )

      expect(result).to be_nil
    end

    it 'converts security_id to integer' do
      instrument.fetch_ltp_from_api_for_segment(
        segment: 'NSE_EQ',
        security_id: '12345'
      )

      expect(DhanHQ::Models::MarketFeed).to have_received(:ltp).with(
        hash_including('NSE_EQ' => [12345])
      )
    end

    it 'converts segment to uppercase' do
      instrument.fetch_ltp_from_api_for_segment(
        segment: 'nse_eq',
        security_id: instrument.security_id
      )

      expect(DhanHQ::Models::MarketFeed).to have_received(:ltp).with(
        hash_including('NSE_EQ' => anything)
      )
    end
  end

  describe '#resolve_ltp' do
    it 'handles fallback_to_api false' do
      result = instrument.resolve_ltp(
        segment: 'NSE_EQ',
        security_id: instrument.security_id,
        meta: {},
        fallback_to_api: false
      )

      expect(result).to be_nil
    end

    it 'handles nil meta' do
      allow(instrument).to receive(:fetch_ltp_from_api_for_segment).and_return(100.0)

      result = instrument.resolve_ltp(
        segment: 'NSE_EQ',
        security_id: instrument.security_id,
        meta: nil,
        fallback_to_api: true
      )

      expect(result).to be_a(BigDecimal)
    end
  end
end

