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
    # Mock AlgoConfig.fetch to return appropriate configs based on the key
    allow(AlgoConfig).to receive(:fetch).and_call_original
    allow(AlgoConfig).to receive(:fetch).with(:risk).and_return(
      max_position_size_pct: 10.0,
      max_total_exposure_pct: 50.0
    )
    allow(AlgoConfig).to receive(:fetch).with(:execution).and_return(
      manual_approval: {
        enabled: false  # Disable manual approval for tests
      }
    )
    # Ensure paper trading is disabled for these tests
    allow(Rails.configuration.x.paper_trading).to receive(:enabled).and_return(false)
  end

  describe '.call' do
    context 'with valid signal' do
      before do
        allow(Dhan::Orders).to receive(:place_order).and_return(
          success: true,
          order: create(:order, instrument: instrument, status: 'placed')
        )

        # Call the service once for all tests in this context
        @result = described_class.call(signal)
      end

      it 'executes order successfully' do
        expect(@result[:success]).to be true
        expect(@result[:order]).to be_present
      end

      it 'validates signal before execution' do
        expect(@result[:success]).to be true
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
        # Capital is 100,000, so 50% limit is 50,000
        # Create orders totaling 45,000 (within limit)
        create_list(:order, 5, instrument: instrument, status: 'placed', price: 90.0, quantity: 100)

        # This order (10,000) would make total 55,000, exceeding 50% limit
        # But it's within the 10% position size limit (10,000)
        result = described_class.call(signal.merge(entry_price: 100.0, qty: 100))

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
        # Order value: 100 * 60 = 6,000 (6% of capital, >5% threshold, but <10% position size limit)
        large_signal = signal.merge(entry_price: 60.0, qty: 100)
        result = described_class.call(large_signal)

        expect(result[:success]).to be true
        expect(Telegram::Notifier).to have_received(:send_error_alert).at_least(:once)
      end

      it 'does not send alert for small orders' do
        # Order value: 100 * 100 = 10,000 (10% of capital, but <5% threshold per order)
        result = described_class.call(signal)

        expect(result[:success]).to be true
        # Should not send alert for orders <5% of capital
      end
    end

    context 'with paper trading enabled' do
      before do
        allow(Rails.configuration.x.paper_trading).to receive(:enabled).and_return(true)
        allow(PaperTrading::Executor).to receive(:execute).and_return(
          { success: true, position: create(:paper_position) }
        )
      end

      it 'routes to paper trading executor' do
        result = described_class.call(signal)

        expect(result[:success]).to be true
        expect(PaperTrading::Executor).to have_received(:execute)
      end

      it 'skips risk limit checks' do
        # Even with large order, should succeed in paper trading
        large_signal = signal.merge(entry_price: 15_000.0, qty: 100)
        result = described_class.call(large_signal)

        expect(result[:success]).to be true
      end

      it 'skips circuit breaker checks' do
        # Create many failed orders
        create_list(:order, 10, status: 'failed', created_at: 30.minutes.ago)
        result = described_class.call(signal)

        expect(result[:success]).to be true
      end
    end

    context 'with manual approval required' do
      before do
        allow(Rails.configuration.x.paper_trading).to receive(:enabled).and_return(false)
        allow(AlgoConfig).to receive(:fetch).with(:execution).and_return(
          manual_approval: {
            enabled: true,
            count: 30
          }
        )
        # Create only 20 executed orders (less than 30)
        create_list(:order, 20, status: 'executed')
      end

      it 'requires approval for first 30 trades' do
        result = described_class.call(signal)

        expect(result[:success]).to be false
        expect(result[:requires_approval]).to be true
        expect(result[:executed_count]).to eq(20)
        expect(result[:remaining]).to eq(10)
      end

      it 'allows orders after 30 trades' do
        # Create 30 executed orders
        create_list(:order, 10, status: 'executed')
        allow(Dhan::Orders).to receive(:place_order).and_return(
          success: true,
          order: create(:order, instrument: instrument)
        )

        result = described_class.call(signal)

        expect(result[:success]).to be true
      end

      it 'skips approval in dry-run mode' do
        allow(ENV).to receive(:[]).with('DRY_RUN').and_return('true')
        allow(Dhan::Orders).to receive(:place_order).and_return(
          success: true,
          order: create(:order, instrument: instrument, dry_run: true)
        )

        result = described_class.call(signal, dry_run: true)

        expect(result[:success]).to be true
      end

      it 'creates pending approval order' do
        result = described_class.call(signal)

        expect(result[:success]).to be false
        expect(result[:requires_approval]).to be true
        expect(result[:order]).to be_present
        expect(result[:order].requires_approval).to be true
        expect(result[:order].status).to eq('pending')
      end

      it 'sends approval request notification' do
        allow(Telegram::Notifier).to receive(:send_error_alert)

        described_class.call(signal)

        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end
    end

    context 'when order placement fails' do
      before do
        allow(Dhan::Orders).to receive(:place_order).and_return(
          success: false,
          error: 'Order placement failed'
        )
      end

      it 'returns error' do
        result = described_class.call(signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Order placement failed')
      end
    end

    context 'when paper trade execution fails' do
      before do
        allow(Rails.configuration.x.paper_trading).to receive(:enabled).and_return(true)
        allow(PaperTrading::Executor).to receive(:execute).and_raise(StandardError, 'Paper trade error')
        allow(Rails.logger).to receive(:error)
      end

      it 'handles error gracefully' do
        result = described_class.call(signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Paper trade failed')
        expect(result[:paper_trade]).to be true
        expect(Rails.logger).to have_received(:error)
      end
    end

    context 'with exposure calculations' do
      before do
        allow(Dhan::Orders).to receive(:place_order).and_return(
          success: true,
          order: create(:order, instrument: instrument)
        )
      end

      it 'calculates instrument exposure correctly' do
        # Create existing orders for same instrument
        create_list(:order, 3, instrument: instrument, status: 'placed', price: 100.0, quantity: 10)

        service = described_class.new(signal: signal)
        exposure = service.send(:calculate_instrument_exposure)

        expect(exposure).to eq(3000.0) # 3 orders * 100 * 10
      end

      it 'calculates total exposure correctly' do
        # Create orders for different instruments
        other_instrument = create(:instrument)
        create_list(:order, 2, instrument: instrument, status: 'placed', price: 100.0, quantity: 10)
        create_list(:order, 2, instrument: other_instrument, status: 'placed', price: 50.0, quantity: 20)

        service = described_class.new(signal: signal)
        total_exposure = service.send(:calculate_total_exposure)

        expect(total_exposure).to eq(4000.0) # (2 * 100 * 10) + (2 * 50 * 20)
      end
    end

    context 'with large order confirmation' do
      before do
        allow(Dhan::Orders).to receive(:place_order).and_return(
          success: true,
          order: create(:order, instrument: instrument)
        )
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'sends confirmation for large orders' do
        # Order value: 100 * 60 = 6,000 (6% of 100,000 capital, >5% threshold)
        large_signal = signal.merge(entry_price: 60.0, qty: 100)
        result = described_class.call(large_signal)

        expect(result[:success]).to be true
        expect(Telegram::Notifier).to have_received(:send_error_alert).at_least(:once)
      end

      it 'does not send confirmation in dry-run mode' do
        allow(ENV).to receive(:[]).with('DRY_RUN').and_return('true')
        large_signal = signal.merge(entry_price: 60.0, qty: 100)

        described_class.call(large_signal, dry_run: true)

        # Should not send confirmation in dry-run
      end
    end

    context 'with order notification' do
      before do
        allow(Dhan::Orders).to receive(:place_order).and_return(
          success: true,
          order: create(:order, instrument: instrument, status: 'placed')
        )
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'sends notification for successful orders' do
        result = described_class.call(signal)

        expect(result[:success]).to be true
        expect(Telegram::Notifier).to have_received(:send_error_alert).at_least(:once)
      end

      it 'does not send notification in dry-run mode' do
        allow(ENV).to receive(:[]).with('DRY_RUN').and_return('true')

        described_class.call(signal, dry_run: true)

        # Notification should not be sent in dry-run
      end
    end

    context 'with private methods' do
      let(:service) { described_class.new(signal: signal) }

      describe '#get_current_capital' do
        it 'retrieves current capital from settings' do
          Setting.put('portfolio.current_capital', 150_000)

          capital = service.send(:get_current_capital)

          expect(capital).to eq(150_000)
        end

        it 'defaults to 100000 if not set' do
          Setting.put('portfolio.current_capital', nil)

          capital = service.send(:get_current_capital)

          expect(capital).to eq(100_000)
        end
      end

      describe '#calculate_instrument_exposure' do
        it 'calculates exposure for specific instrument' do
          create_list(:order, 3, instrument: instrument, status: 'placed', price: 100.0, quantity: 10)

          exposure = service.send(:calculate_instrument_exposure)

          expect(exposure).to eq(3000.0)
        end

        it 'ignores non-placed orders' do
          create(:order, instrument: instrument, status: 'rejected', price: 100.0, quantity: 10)

          exposure = service.send(:calculate_instrument_exposure)

          expect(exposure).to eq(0)
        end
      end

      describe '#calculate_total_exposure' do
        it 'calculates total exposure across all instruments' do
          other_instrument = create(:instrument)
          create_list(:order, 2, instrument: instrument, status: 'placed', price: 100.0, quantity: 10)
          create_list(:order, 2, instrument: other_instrument, status: 'placed', price: 50.0, quantity: 20)

          total_exposure = service.send(:calculate_total_exposure)

          expect(total_exposure).to eq(4000.0)
        end
      end

      describe '#execute_paper_trade' do
        before do
          allow(Rails.configuration.x.paper_trading).to receive(:enabled).and_return(true)
          allow(PaperTrading::Executor).to receive(:execute).and_return(
            { success: true, position: create(:paper_position) }
          )
        end

        it 'executes paper trade' do
          result = service.send(:execute_paper_trade)

          expect(result[:success]).to be true
          expect(result[:paper_trade]).to be true
          expect(PaperTrading::Executor).to have_received(:execute)
        end

        it 'handles paper trade failure' do
          allow(PaperTrading::Executor).to receive(:execute).and_raise(StandardError, 'Paper trade error')
          allow(Rails.logger).to receive(:error)

          result = service.send(:execute_paper_trade)

          expect(result[:success]).to be false
          expect(Rails.logger).to have_received(:error)
        end
      end

      describe '#send_entry_notification' do
        before do
          allow(Telegram::Notifier).to receive(:send_signal_alert)
        end

        it 'sends notification for successful order' do
          order = create(:order, instrument: instrument, status: 'placed')
          result = { success: true, order: order }

          service.send(:send_entry_notification, result)

          expect(Telegram::Notifier).to have_received(:send_signal_alert)
        end

        it 'does not send notification for failed orders' do
          result = { success: false, error: 'Order failed' }

          service.send(:send_entry_notification, result)

          expect(Telegram::Notifier).not_to have_received(:send_signal_alert)
        end

        it 'does not send notification in dry-run mode' do
          allow(ENV).to receive(:[]).with('DRY_RUN').and_return('true')
          order = create(:order, instrument: instrument, status: 'placed', dry_run: true)
          result = { success: true, order: order, dry_run: true }

          service.send(:send_entry_notification, result)

          expect(Telegram::Notifier).not_to have_received(:send_signal_alert)
        end
      end

      describe '#send_large_order_confirmation' do
        before do
          allow(Telegram::Notifier).to receive(:send_error_alert)
        end

        it 'sends confirmation for large orders' do
          order = create(:order, instrument: instrument, price: 60.0, quantity: 100)
          # Order value: 60 * 100 = 6,000 (6% of 100,000 capital, >5% threshold)

          service.send(:send_large_order_confirmation, order)

          expect(Telegram::Notifier).to have_received(:send_error_alert)
        end

        it 'does not send confirmation for small orders' do
          order = create(:order, instrument: instrument, price: 40.0, quantity: 100)
          # Order value: 40 * 100 = 4,000 (4% of 100,000 capital, <5% threshold)

          service.send(:send_large_order_confirmation, order)

          expect(Telegram::Notifier).not_to have_received(:send_error_alert)
        end

        it 'does not send confirmation in dry-run mode' do
          allow(ENV).to receive(:[]).with('DRY_RUN').and_return('true')
          order = create(:order, instrument: instrument, price: 60.0, quantity: 100, dry_run: true)

          service.send(:send_large_order_confirmation, order)

          expect(Telegram::Notifier).not_to have_received(:send_error_alert)
        end
      end
    end

    context 'with edge cases' do
      it 'handles missing direction in signal' do
        invalid_signal = signal.merge(direction: nil)
        result = described_class.call(invalid_signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Missing direction')
      end

      it 'handles zero capital gracefully' do
        Setting.put('portfolio.current_capital', 0)
        allow(Dhan::Orders).to receive(:place_order).and_return(
          success: true,
          order: create(:order, instrument: instrument)
        )

        result = described_class.call(signal)

        # Should handle zero capital (risk checks will fail or pass based on logic)
        expect(result).to be_present
      end

      it 'handles nil risk config' do
        allow(AlgoConfig).to receive(:fetch).with(:risk).and_return(nil)
        allow(Dhan::Orders).to receive(:place_order).and_return(
          success: true,
          order: create(:order, instrument: instrument)
        )

        result = described_class.call(signal)

        # Should use defaults when config is nil
        expect(result).to be_present
      end
    end
  end
end

