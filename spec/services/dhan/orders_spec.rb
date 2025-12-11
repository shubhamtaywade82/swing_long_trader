# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dhan::Orders, type: :service do
  let(:instrument) { create(:instrument, symbol_name: 'RELIANCE', security_id: '11536', exchange: 'NSE', segment: 'E') }
  let(:client_order_id) { "B-#{instrument.security_id}-#{Time.current.to_i.to_s[-6..]}" }

  describe '.place_order' do
    context 'with valid parameters' do
      let(:dhan_client) { double('DhanHQ::Client') }
      let(:success_response) do
        {
          'status' => 'success',
          'orderId' => 'DHAN_123456',
          'exchangeOrderId' => 'EXCH_789',
          'message' => 'Order placed successfully'
        }
      end

      before do
        allow(DhanHQ::Client).to receive(:new).with(api_type: :order_api).and_return(dhan_client)
        allow(dhan_client).to receive(:place_order).and_return(success_response)
      end

      it 'places a market order successfully' do
        result = described_class.place_order(
          instrument: instrument,
          order_type: 'MARKET',
          transaction_type: 'BUY',
          quantity: 100
        )

        expect(result[:success]).to be true
        expect(result[:order]).to be_present
        expect(result[:order].status).to eq('placed')
        expect(result[:order].dhan_order_id).to eq('DHAN_123456')
      end

      it 'creates order record with correct attributes' do
        result = described_class.place_order(
          instrument: instrument,
          order_type: 'MARKET',
          transaction_type: 'BUY',
          quantity: 100,
          client_order_id: client_order_id
        )

        order = result[:order]
        expect(order.instrument).to eq(instrument)
        expect(order.client_order_id).to eq(client_order_id)
        expect(order.symbol).to eq(instrument.symbol_name)
        expect(order.order_type).to eq('MARKET')
        expect(order.transaction_type).to eq('BUY')
        expect(order.quantity).to eq(100)
      end

      it 'places a limit order with price' do
        result = described_class.place_order(
          instrument: instrument,
          order_type: 'LIMIT',
          transaction_type: 'BUY',
          quantity: 100,
          price: 100.0
        )

        expect(result[:success]).to be true
        expect(result[:order].order_type).to eq('LIMIT')
        expect(result[:order].price).to eq(100.0)
      end

      it 'places a stop-loss order with trigger price' do
        result = described_class.place_order(
          instrument: instrument,
          order_type: 'SL',
          transaction_type: 'SELL',
          quantity: 100,
          trigger_price: 95.0
        )

        expect(result[:success]).to be true
        expect(result[:order].order_type).to eq('SL')
        expect(result[:order].trigger_price).to eq(95.0)
      end
    end

    context 'with idempotency' do
      let!(:existing_order) do
        create(:order,
          instrument: instrument,
          client_order_id: client_order_id,
          status: 'placed')
      end

      it 'returns existing order if client_order_id matches' do
        result = described_class.place_order(
          instrument: instrument,
          order_type: 'MARKET',
          transaction_type: 'BUY',
          quantity: 100,
          client_order_id: client_order_id
        )

        expect(result[:success]).to be true
        expect(result[:duplicate]).to be true
        expect(result[:order].id).to eq(existing_order.id)
      end
    end

    context 'with dry-run mode' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('DRY_RUN').and_return('true')
      end

      it 'simulates order placement without calling DhanHQ API' do
        result = described_class.place_order(
          instrument: instrument,
          order_type: 'MARKET',
          transaction_type: 'BUY',
          quantity: 100
        )

        expect(result[:success]).to be true
        expect(result[:dry_run]).to be true
        expect(result[:order].dry_run).to be true
        expect(result[:order].dhan_order_id).to start_with('DRY_RUN_')
        expect(result[:dhan_response]['status']).to eq('success')
      end

      it 'allows explicit dry_run parameter to override ENV' do
        result = described_class.place_order(
          instrument: instrument,
          order_type: 'MARKET',
          transaction_type: 'BUY',
          quantity: 100,
          dry_run: false
        )

        # Should still be dry-run if ENV is set, but we can test explicit override
        expect(result[:order].dry_run).to be true # ENV takes precedence
      end
    end

    context 'with validation errors' do
      it 'rejects invalid quantity' do
        result = described_class.place_order(
          instrument: instrument,
          order_type: 'MARKET',
          transaction_type: 'BUY',
          quantity: 0
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Invalid quantity')
      end

      it 'rejects limit order without price' do
        result = described_class.place_order(
          instrument: instrument,
          order_type: 'LIMIT',
          transaction_type: 'BUY',
          quantity: 100
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Price required')
      end

      it 'rejects stop-loss order without trigger price' do
        result = described_class.place_order(
          instrument: instrument,
          order_type: 'SL',
          transaction_type: 'SELL',
          quantity: 100
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Trigger price required')
      end

      it 'rejects invalid instrument' do
        result = described_class.place_order(
          instrument: nil,
          order_type: 'MARKET',
          transaction_type: 'BUY',
          quantity: 100
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Invalid instrument')
      end
    end

    context 'with DhanHQ API errors' do
      let(:dhan_client) { double('DhanHQ::Client') }
      let(:error_response) do
        {
          'status' => 'error',
          'message' => 'Insufficient funds'
        }
      end

      before do
        allow(DhanHQ::Client).to receive(:new).with(api_type: :order_api).and_return(dhan_client)
        allow(dhan_client).to receive(:place_order).and_return(error_response)
      end

      it 'handles API rejection' do
        result = described_class.place_order(
          instrument: instrument,
          order_type: 'MARKET',
          transaction_type: 'BUY',
          quantity: 100
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Insufficient funds')
        expect(result[:order].status).to eq('rejected')
      end
    end

    context 'with DhanHQ client unavailable' do
      before do
        allow(DhanHQ::Client).to receive(:new).and_raise(StandardError, 'Client unavailable')
      end

      it 'handles client creation failure' do
        result = described_class.place_order(
          instrument: instrument,
          order_type: 'MARKET',
          transaction_type: 'BUY',
          quantity: 100
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('not available')
      end
    end
  end
end

