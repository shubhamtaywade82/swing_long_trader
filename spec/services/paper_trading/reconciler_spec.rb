# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::Reconciler, type: :service do
  let(:portfolio) { create(:paper_portfolio, capital: 100_000) }
  let(:instrument) { create(:instrument) }

  describe ".call" do
    context "when portfolio is provided" do
      it "uses provided portfolio" do
        allow(PaperTrading::Portfolio).to receive(:find_or_create_default)
        allow_any_instance_of(described_class).to receive(:call).and_return({})

        described_class.call(portfolio: portfolio)

        expect(PaperTrading::Portfolio).not_to have_received(:find_or_create_default)
      end
    end

    context "when portfolio is not provided" do
      let(:default_portfolio) { create(:paper_portfolio, name: "default") }

      before do
        allow(PaperTrading::Portfolio).to receive(:find_or_create_default).and_return(default_portfolio)
        allow_any_instance_of(described_class).to receive(:call).and_return({})
      end

      it "uses default portfolio" do
        described_class.call

        expect(PaperTrading::Portfolio).to have_received(:find_or_create_default)
      end
    end
  end

  describe "#call" do
    context "when there are no open positions" do
      before do
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it "returns summary with zero positions" do
        result = described_class.new(portfolio: portfolio).call

        expect(result[:open_positions_count]).to eq(0)
        expect(result[:closed_positions_count]).to eq(0)
        expect(result[:pnl_unrealized]).to eq(0)
      end

      it "updates portfolio equity" do
        allow(portfolio).to receive(:update_equity!)

        described_class.new(portfolio: portfolio).call

        expect(portfolio).to have_received(:update_equity!)
      end

      it "updates portfolio drawdown" do
        allow(portfolio).to receive(:update_drawdown!)

        described_class.new(portfolio: portfolio).call

        expect(portfolio).to have_received(:update_drawdown!)
      end
    end

    context "when there are open positions" do
      let(:position1) do
        create(:paper_position,
               paper_portfolio: portfolio,
               instrument: instrument,
               entry_price: 100.0,
               current_price: 105.0,
               quantity: 10,
               status: "open")
      end

      let(:position2) do
        create(:paper_position,
               paper_portfolio: portfolio,
               instrument: create(:instrument),
               entry_price: 50.0,
               current_price: 48.0,
               quantity: 20,
               status: "open")
      end

      before do
        position1
        position2
        create(:candle_series_record,
               instrument: position1.instrument,
               timeframe: "1D",
               close: 105.0,
               timestamp: Time.current)
        create(:candle_series_record,
               instrument: position2.instrument,
               timeframe: "1D",
               close: 48.0,
               timestamp: Time.current)
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it "updates all position prices" do
        expect(position1).to receive(:update_current_price!).with(105.0)
        expect(position2).to receive(:update_current_price!).with(48.0)

        described_class.new(portfolio: portfolio).call
      end

      it "calculates unrealized P&L" do
        result = described_class.new(portfolio: portfolio).call

        # Position 1: (105 - 100) * 10 = 50 profit
        # Position 2: (48 - 50) * 20 = -40 loss
        # Total: 50 - 40 = 10
        expect(result[:pnl_unrealized]).to eq(10.0)
      end

      it "returns summary with position counts" do
        result = described_class.new(portfolio: portfolio).call

        expect(result[:open_positions_count]).to eq(2)
        expect(result[:total_exposure]).to be > 0
      end
    end

    context "when there are closed positions" do
      before do
        create(:paper_position,
               paper_portfolio: portfolio,
               status: "closed")
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it "includes closed positions in summary" do
        result = described_class.new(portfolio: portfolio).call

        expect(result[:closed_positions_count]).to eq(1)
      end
    end

    context "when sending daily summary" do
      before do
        allow(Telegram::Notifier).to receive(:enabled?).and_return(true)
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it "sends Telegram notification" do
        described_class.new(portfolio: portfolio).call

        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end

      it "includes portfolio metrics in message" do
        described_class.new(portfolio: portfolio).call

        expect(Telegram::Notifier).to have_received(:send_error_alert) do |message|
          expect(message).to include("DAILY PAPER TRADING SUMMARY")
          expect(message).to include("Capital")
          expect(message).to include("Total Equity")
        end
      end
    end

    context "when reconciliation fails" do
      before do
        allow(portfolio).to receive(:open_positions).and_raise(StandardError, "Database error")
      end

      it "raises error" do
        expect do
          described_class.new(portfolio: portfolio).call
        end.to raise_error(StandardError, "Database error")
      end

      it "logs error on failure" do
        allow(portfolio).to receive(:open_positions).and_raise(StandardError, "Database error")
        allow(Rails.logger).to receive(:error)

        expect do
          described_class.new(portfolio: portfolio).call
        end.to raise_error(StandardError)

        expect(Rails.logger).to have_received(:error)
      end
    end

    context "with edge cases" do
      before do
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it "handles positions without candles" do
        _position = create(:paper_position,
                           paper_portfolio: portfolio,
                           instrument: instrument,
                           entry_price: 100.0,
                           current_price: 100.0,
                           status: "open")

        # No candles created
        result = described_class.new(portfolio: portfolio).call

        expect(result[:open_positions_count]).to eq(1)
        expect(result[:pnl_unrealized]).to eq(0) # No price update, so no unrealized P&L change
      end

      it "handles positions with missing instruments" do
        _position = create(:paper_position,
                           paper_portfolio: portfolio,
                           instrument: instrument,
                           entry_price: 100.0,
                           current_price: 100.0,
                           status: "open")

        # Delete instrument
        instrument.destroy!

        result = described_class.new(portfolio: portfolio).call

        # Should handle gracefully
        expect(result).to be_present
      end

      it "calculates total P&L correctly" do
        _position = create(:paper_position,
                           paper_portfolio: portfolio,
                           instrument: instrument,
                           entry_price: 100.0,
                           current_price: 105.0,
                           quantity: 10,
                           status: "open")

        portfolio.update!(pnl_realized: 500.0, pnl_unrealized: 0.0)
        create(:candle_series_record,
               instrument: instrument,
               timeframe: "1D",
               close: 105.0,
               timestamp: Time.current)

        result = described_class.new(portfolio: portfolio).call

        # Realized: 500, Unrealized: (105-100)*10 = 50, Total: 550
        expect(result[:total_pnl]).to eq(550.0)
      end

      it "handles negative unrealized P&L" do
        _position = create(:paper_position,
                           paper_portfolio: portfolio,
                           instrument: instrument,
                           entry_price: 100.0,
                           current_price: 95.0,
                           quantity: 10,
                           status: "open")

        create(:candle_series_record,
               instrument: instrument,
               timeframe: "1D",
               close: 95.0,
               timestamp: Time.current)

        result = described_class.new(portfolio: portfolio).call

        # Unrealized: (95-100)*10 = -50
        expect(result[:pnl_unrealized]).to eq(-50.0)
      end

      it "handles zero capital" do
        portfolio.update!(capital: 0)
        result = described_class.new(portfolio: portfolio).call

        expect(result[:capital]).to eq(0)
        expect(result[:available_capital]).to eq(0)
      end

      it "handles very large equity values" do
        portfolio.update!(capital: 1_000_000_000, total_equity: 1_000_000_000)
        result = described_class.new(portfolio: portfolio).call

        expect(result[:total_equity]).to be > 0
      end

      it "logs reconciliation start and completion" do
        allow(Rails.logger).to receive(:info)

        described_class.new(portfolio: portfolio).call

        expect(Rails.logger).to have_received(:info).at_least(:twice)
      end
    end

    context "with Telegram notification" do
      before do
        allow(Telegram::Notifier).to receive(:enabled?).and_return(true)
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it "sends notification with all summary fields" do
        described_class.new(portfolio: portfolio).call

        expect(Telegram::Notifier).to have_received(:send_error_alert) do |message, options|
          expect(message).to include("DAILY PAPER TRADING SUMMARY")
          expect(message).to include("Capital")
          expect(message).to include("Total Equity")
          expect(message).to include("Realized P&L")
          expect(message).to include("Unrealized P&L")
          expect(message).to include("Total P&L")
          expect(message).to include("Max Drawdown")
          expect(message).to include("Utilization")
          expect(message).to include("Open Positions")
          expect(message).to include("Closed Positions")
          expect(message).to include("Total Exposure")
          expect(message).to include("Available Capital")
          expect(options[:context]).to eq("Daily Paper Trading Summary")
        end
      end

      it "handles notification failure gracefully" do
        allow(Telegram::Notifier).to receive(:send_error_alert).and_raise(StandardError, "Telegram error")
        allow(Rails.logger).to receive(:error)

        result = described_class.new(portfolio: portfolio).call

        expect(result).to be_present
        expect(Rails.logger).to have_received(:error)
      end
    end

    context "with summary generation" do
      before do
        allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
      end

      it "generates complete summary" do
        result = described_class.new(portfolio: portfolio).call

        expect(result).to have_key(:portfolio_name)
        expect(result).to have_key(:capital)
        expect(result).to have_key(:total_equity)
        expect(result).to have_key(:pnl_realized)
        expect(result).to have_key(:pnl_unrealized)
        expect(result).to have_key(:total_pnl)
        expect(result).to have_key(:max_drawdown)
        expect(result).to have_key(:utilization_pct)
        expect(result).to have_key(:open_positions_count)
        expect(result).to have_key(:closed_positions_count)
        expect(result).to have_key(:total_exposure)
        expect(result).to have_key(:available_capital)
      end

      it "rounds all numeric values" do
        portfolio.update!(
          capital: 100_000.123456,
          total_equity: 105_000.789012,
          pnl_realized: 500.456789,
          pnl_unrealized: 50.123456,
        )

        result = described_class.new(portfolio: portfolio).call

        expect(result[:capital]).to eq(100_000.12)
        expect(result[:total_equity]).to eq(105_000.79)
        expect(result[:pnl_realized]).to eq(500.46)
        expect(result[:pnl_unrealized]).to eq(50.12)
      end
    end
  end
end
