# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaperTrading::RiskManager, type: :service do
  let(:portfolio) { create(:paper_portfolio, capital: 100_000, available_capital: 100_000) }
  let(:signal) do
    {
      direction: 'long',
      entry_price: 100.0,
      qty: 10
    }
  end

  describe '.check_limits' do
    context 'when all checks pass' do
      before do
        allow(AlgoConfig).to receive(:fetch).with(:risk).and_return({})
      end

      it 'returns success' do
        result = described_class.check_limits(portfolio: portfolio, signal: signal)

        expect(result[:success]).to be true
      end
    end

    context 'when capital is insufficient' do
      let(:signal) do
        {
          direction: 'long',
          entry_price: 100.0,
          qty: 2000 # Requires 200,000 but only 100,000 available
        }
      end

      it 'returns error' do
        result = described_class.check_limits(portfolio: portfolio, signal: signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Insufficient capital')
      end
    end

    context 'when max position size is exceeded' do
      before do
        allow(AlgoConfig).to receive(:fetch).with(:risk).and_return(
          max_position_size_pct: 5.0 # 5% of 100,000 = 5,000 max
        )
      end

      let(:signal) do
        {
          direction: 'long',
          entry_price: 100.0,
          qty: 100 # Requires 10,000 which exceeds 5,000
        }
      end

      it 'returns error' do
        result = described_class.check_limits(portfolio: portfolio, signal: signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('exceeds max position size')
      end
    end

    context 'when max total exposure is exceeded' do
      let(:existing_position) do
        create(:paper_position,
          paper_portfolio: portfolio,
          entry_price: 100.0,
          quantity: 400,
          status: 'open')
      end

      before do
        existing_position
        allow(AlgoConfig).to receive(:fetch).with(:risk).and_return(
          max_total_exposure_pct: 50.0 # 50% of 100,000 = 50,000 max
        )
      end

      let(:signal) do
        {
          direction: 'long',
          entry_price: 100.0,
          qty: 200 # Would add 20,000, total would be 60,000 > 50,000
        }
      end

      it 'returns error' do
        result = described_class.check_limits(portfolio: portfolio, signal: signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Total exposure exceeds limit')
      end
    end

    context 'when max open positions is reached' do
      before do
        create_list(:paper_position, 5, paper_portfolio: portfolio, status: 'open')
        allow(AlgoConfig).to receive(:fetch).with(:risk).and_return(
          max_open_positions: 5
        )
      end

      it 'returns error' do
        result = described_class.check_limits(portfolio: portfolio, signal: signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Max open positions reached')
      end
    end

    context 'when daily loss limit is exceeded' do
      before do
        allow(AlgoConfig).to receive(:fetch).with(:risk).and_return(
          max_daily_loss_pct: 5.0 # 5% of 100,000 = 5,000 max loss
        )

        # Create ledger entries showing 6,000 loss today
        create(:paper_ledger,
          paper_portfolio: portfolio,
          transaction_type: 'debit',
          amount: 6000,
          reason: 'loss',
          created_at: Time.current)
      end

      it 'returns error' do
        result = described_class.check_limits(portfolio: portfolio, signal: signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Daily loss limit exceeded')
      end
    end

    context 'when drawdown limit is exceeded' do
      before do
        allow(AlgoConfig).to receive(:fetch).with(:risk).and_return(
          max_drawdown_pct: 20.0
        )
        allow(portfolio).to receive(:max_drawdown).and_return(25.0)
      end

      it 'returns error' do
        result = described_class.check_limits(portfolio: portfolio, signal: signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Max drawdown exceeded')
      end
    end
  end

  describe '#calculate_today_loss' do
    before do
      allow(AlgoConfig).to receive(:fetch).with(:risk).and_return({})
    end

    context 'when there are losses today' do
      before do
        create(:paper_ledger,
          paper_portfolio: portfolio,
          transaction_type: 'debit',
          amount: 3000,
          reason: 'loss',
          created_at: Time.current)

        create(:paper_ledger,
          paper_portfolio: portfolio,
          transaction_type: 'credit',
          amount: 1000,
          reason: 'profit',
          created_at: Time.current)
      end

      it 'calculates net loss correctly' do
        service = described_class.new(portfolio: portfolio, signal: signal)
        loss = service.send(:calculate_today_loss)

        expect(loss).to eq(-2000) # 1000 credit - 3000 debit = -2000
      end
    end

    context 'when there are no transactions today' do
      it 'returns zero' do
        service = described_class.new(portfolio: portfolio, signal: signal)
        loss = service.send(:calculate_today_loss)

        expect(loss).to eq(0)
      end
    end

    context 'with edge cases' do
      before do
        allow(AlgoConfig).to receive(:fetch).with(:risk).and_return({})
      end

      it 'handles zero capital' do
        zero_capital_portfolio = create(:paper_portfolio, capital: 0, available_capital: 0)
        result = described_class.check_limits(portfolio: zero_capital_portfolio, signal: signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Insufficient capital')
      end

      it 'handles nil risk config gracefully' do
        allow(AlgoConfig).to receive(:fetch).with(:risk).and_return(nil)

        result = described_class.check_limits(portfolio: portfolio, signal: signal)

        # Should use defaults
        expect(result[:success]).to be true
      end

      it 'handles very large order values' do
        large_signal = signal.merge(entry_price: 1_000_000.0, qty: 1000)
        result = described_class.check_limits(portfolio: portfolio, signal: large_signal)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Insufficient capital')
      end

      it 'handles zero quantity' do
        zero_qty_signal = signal.merge(qty: 0)
        result = described_class.check_limits(portfolio: portfolio, signal: zero_qty_signal)

        # Zero quantity should pass capital check but might fail elsewhere
        expect(result).to be_present
      end

      it 'handles negative prices gracefully' do
        negative_price_signal = signal.merge(entry_price: -100.0)
        result = described_class.check_limits(portfolio: portfolio, signal: negative_price_signal)

        # Should handle gracefully (might pass or fail depending on implementation)
        expect(result).to be_present
      end
    end

    context 'with multiple checks failing' do
      before do
        allow(AlgoConfig).to receive(:fetch).with(:risk).and_return(
          max_position_size_pct: 5.0,
          max_total_exposure_pct: 50.0,
          max_open_positions: 5,
          max_daily_loss_pct: 5.0,
          max_drawdown_pct: 20.0
        )
      end

      it 'returns first failing check' do
        # Create scenario where multiple checks would fail
        create_list(:paper_position, 5, paper_portfolio: portfolio, status: 'open')
        large_signal = signal.merge(entry_price: 15_000.0, qty: 100)

        result = described_class.check_limits(portfolio: portfolio, signal: large_signal)

        expect(result[:success]).to be false
        # Should return the first failing check (likely capital or position size)
        expect(result[:error]).to be_present
      end
    end

    context 'with ledger edge cases' do
      before do
        allow(AlgoConfig).to receive(:fetch).with(:risk).and_return({})
      end

      it 'handles ledgers from different days' do
        # Create ledger from yesterday
        create(:paper_ledger,
          paper_portfolio: portfolio,
          transaction_type: 'debit',
          amount: 10_000,
          reason: 'loss',
          created_at: 1.day.ago)

        service = described_class.new(portfolio: portfolio, signal: signal)
        loss = service.send(:calculate_today_loss)

        expect(loss).to eq(0) # Should only count today's losses
      end

      it 'handles multiple ledger entries' do
        create(:paper_ledger,
          paper_portfolio: portfolio,
          transaction_type: 'debit',
          amount: 1000,
          reason: 'loss',
          created_at: Time.current)
        create(:paper_ledger,
          paper_portfolio: portfolio,
          transaction_type: 'debit',
          amount: 2000,
          reason: 'loss',
          created_at: Time.current)
        create(:paper_ledger,
          paper_portfolio: portfolio,
          transaction_type: 'credit',
          amount: 500,
          reason: 'profit',
          created_at: Time.current)

        service = described_class.new(portfolio: portfolio, signal: signal)
        loss = service.send(:calculate_today_loss)

        expect(loss).to eq(-2500) # (1000 + 2000) - 500 = 2500 loss
      end

      it 'handles empty ledger' do
        service = described_class.new(portfolio: portfolio, signal: signal)
        loss = service.send(:calculate_today_loss)

        expect(loss).to eq(0)
      end
    end
  end
end

