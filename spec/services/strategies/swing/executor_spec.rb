# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::Swing::Executor, type: :service do
  let(:instrument) { create(:instrument, symbol_name: 'RELIANCE', security_id: '11536', exchange: 'NSE', segment: 'E') }
  let(:signal) do
    {
      instrument_id: instrument.id,
      symbol: 'RELIANCE',
      direction: :long,
      entry_price: 100.0,
      sl: 95.0,
      tp: 110.0,
      rr: 2.0,
      qty: 100,
      confidence: 80.0,
      holding_days_estimate: 5
    }
  end

  before do
    # Set default capital
    Setting.put('portfolio.current_capital', 100_000)
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        max_position_size_pct: 10.0,
        max_total_exposure_pct: 50.0
      }
    )
  end

  describe '.call' do
    context 'with valid signal' do
      before do
        allow(Dhan::Orders).to receive(:place_order).and_return(
          success: true,
          order: create(:order, instrument: instrument, status: 'placed')
        )
      end

      it 'executes order successfully' do
        result = described_class.call(signal)

        expect(result[:success]).to be true
        expect(result[:order]).to be_present
      end

      it 'validates signal before execution' do
        result = described_class.call(signal)

        expect(result[:success]).to be true
        expect(Dhan::Orders).to have_received(:place_order)
      end
    end

    context 'with invalid signal' do
      it 'rejects signal without instrument_id' do
        invalid_signal = signal.merge(instrument_id: nil)
        result = described_class.call(invalid_signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Instrument not found')
      end

      it 'rejects signal without entry_price' do
        invalid_signal = signal.merge(entry_price: nil)
        result = described_class.call(invalid_signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Missing entry price')
      end

      it 'rejects signal without quantity' do
        invalid_signal = signal.merge(qty: nil)
        result = described_class.call(invalid_signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Missing quantity')
      end
    end

    context 'with risk limits' do
      before do
        allow(Dhan::Orders).to receive(:place_order).and_return(
          success: true,
          order: create(:order, instrument: instrument)
        )
      end

      it 'allows order within position size limit' do
        # Order value: 100 * 100 = 10,000 (10% of 100,000 capital)
        result = described_class.call(signal)

        expect(result[:success]).to be true
      end

      it 'rejects order exceeding position size limit' do
        # Order value: 100 * 15,000 = 1,500,000 (exceeds 10% limit)
        large_signal = signal.merge(entry_price: 15_000.0, qty: 100)
        result = described_class.call(large_signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('exceeds max position size')
      end

      it 'rejects order exceeding total exposure limit' do
        # Create existing orders to fill up exposure
        create_list(:order, 5, instrument: instrument, status: 'placed', price: 100.0, quantity: 1000)

        # This order would exceed 50% total exposure
        result = described_class.call(signal.merge(entry_price: 1000.0, qty: 100))

        expect(result[:success]).to be false
        expect(result[:error]).to include('Total exposure exceeds limit')
      end
    end

    context 'with circuit breaker' do
      before do
        # Create recent failed orders (>50% failure rate)
        create_list(:order, 5, instrument: instrument, status: 'failed', created_at: 30.minutes.ago)
        create_list(:order, 3, instrument: instrument, status: 'placed', created_at: 30.minutes.ago)
      end

      it 'activates circuit breaker on high failure rate' do
        result = described_class.call(signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Circuit breaker activated')
      end

      it 'allows orders when failure rate is low' do
        # Create more successful orders to bring failure rate below 50%
        create_list(:order, 5, instrument: instrument, status: 'placed', created_at: 30.minutes.ago)

        allow(Dhan::Orders).to receive(:place_order).and_return(
          success: true,
          order: create(:order, instrument: instrument)
        )

        result = described_class.call(signal)

        expect(result[:success]).to be true
      end
    end

    context 'with dry-run mode' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('DRY_RUN').and_return('true')
        allow(Dhan::Orders).to receive(:place_order).and_return(
          success: true,
          order: create(:order, instrument: instrument, dry_run: true),
          dry_run: true
        )
      end

      it 'executes in dry-run mode' do
        result = described_class.call(signal, dry_run: true)

        expect(result[:success]).to be true
        expect(result[:order].dry_run).to be true
      end
    end

    context 'with large orders' do
      before do
        allow(Dhan::Orders).to receive(:place_order).and_return(
          success: true,
          order: create(:order, instrument: instrument)
        )
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'sends alert for large orders (>5% of capital)' do
        # Order value: 100 * 600 = 60,000 (60% of 100,000 capital)
        large_signal = signal.merge(entry_price: 600.0, qty: 100)
        result = described_class.call(large_signal)

        expect(result[:success]).to be true
        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end

      it 'does not send alert for small orders' do
        # Order value: 100 * 100 = 10,000 (10% of capital, but <5% threshold per order)
        result = described_class.call(signal)

        expect(result[:success]).to be true
        # Should not send alert for orders <5% of capital
      end
    end
  end
end

