# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Paper Trading Complete Workflow', type: :integration do
  let(:portfolio) { create(:paper_portfolio, capital: 100_000, available_capital: 100_000) }
  let(:instrument) { create(:instrument) }
  let(:signal) do
    {
      instrument_id: instrument.id,
      direction: 'long',
      entry_price: 100.0,
      qty: 10,
      sl: 95.0,
      tp: 110.0
    }
  end

  before do
    allow(TelegramNotifier).to receive(:enabled?).and_return(false)
    allow(AlgoConfig).to receive(:fetch).and_return({})
  end

  describe 'Complete workflow: Executor -> Simulator -> Reconciler' do
    context 'when all steps succeed' do
      before do
        # Create daily candle for price updates
        create(:candle_series_record,
          instrument: instrument,
          timeframe: '1D',
          timestamp: Time.current,
          close: 102.0)
      end

      it 'executes complete paper trading workflow' do
        # Step 1: Execute entry
        execution = PaperTrading::Executor.execute(signal, portfolio: portfolio)
        expect(execution[:success]).to be true
        expect(execution[:position]).to be_present

        position = execution[:position]

        # Step 2: Simulator checks exits (no exit yet)
        simulator_result = PaperTrading::Simulator.check_exits(portfolio: portfolio)
        expect(simulator_result[:checked]).to eq(1)
        expect(simulator_result[:exited]).to eq(0)

        # Step 3: Reconciler updates mark-to-market
        summary = PaperTrading::Reconciler.call(portfolio: portfolio)
        expect(summary[:open_positions_count]).to eq(1)
        expect(summary[:pnl_unrealized]).to be_present

        # Step 4: Simulator triggers exit (TP hit)
        position.update(current_price: 110.0)
        allow(position).to receive(:check_tp_hit?).and_return(true)
        allow(position).to receive(:check_sl_hit?).and_return(false)
        allow(position).to receive(:days_held).and_return(5)

        simulator_result = PaperTrading::Simulator.check_exits(portfolio: portfolio)
        expect(simulator_result[:exited]).to eq(1)

        # Step 5: Final reconciliation
        final_summary = PaperTrading::Reconciler.call(portfolio: portfolio)
        expect(final_summary[:open_positions_count]).to eq(0)
        expect(final_summary[:closed_positions_count]).to eq(1)
        expect(final_summary[:pnl_realized]).to be > 0
      end
    end

    context 'when risk limits prevent entry' do
      before do
        allow(PaperTrading::RiskManager).to receive(:check_limits).and_return(
          { success: false, error: 'Max position size exceeded' }
        )
      end

      it 'stops workflow at risk check' do
        execution = PaperTrading::Executor.execute(signal, portfolio: portfolio)

        expect(execution[:success]).to be false
        expect(execution[:error]).to include('Max position size exceeded')
        expect(PaperPortfolio.find(portfolio.id).paper_positions.count).to eq(0)
      end
    end

    context 'when stop loss is triggered' do
      before do
        create(:candle_series_record,
          instrument: instrument,
          timeframe: '1D',
          timestamp: Time.current,
          close: 94.0)
      end

      it 'exits position at stop loss' do
        # Create position
        execution = PaperTrading::Executor.execute(signal, portfolio: portfolio)
        position = execution[:position]

        # Update price to trigger SL
        position.update(current_price: 94.0)
        allow(position).to receive(:check_sl_hit?).and_return(true)
        allow(position).to receive(:check_tp_hit?).and_return(false)
        allow(position).to receive(:days_held).and_return(2)

        # Check exits
        simulator_result = PaperTrading::Simulator.check_exits(portfolio: portfolio)

        expect(simulator_result[:exited]).to eq(1)
        position.reload
        expect(position.status).to eq('closed')
        expect(position.exit_reason).to eq('sl_hit')
        expect(position.pnl).to be < 0
      end
    end
  end
end

