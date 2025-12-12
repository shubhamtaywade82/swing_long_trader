# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::ReconciliationJob do
  let(:portfolio) { create(:paper_portfolio) }

  describe "#perform" do
    context "when paper trading is enabled" do
      before do
        allow(Rails.configuration.x.paper_trading).to receive(:enabled).and_return(true)
        allow(PaperTrading::Portfolio).to receive(:find_or_create_default).and_return(portfolio)
        allow(PaperTrading::Reconciler).to receive(:call).and_return(
          {
            portfolio_name: "default",
            total_equity: 100_000,
            pnl_unrealized: 5000,
          },
        )
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it "runs reconciliation" do
        result = described_class.new.perform

        expect(result[:total_equity]).to eq(100_000)
        expect(PaperTrading::Reconciler).to have_received(:call).with(portfolio: portfolio)
      end

      context "when portfolio_id is provided" do
        it "uses specified portfolio" do
          described_class.new.perform(portfolio_id: portfolio.id)

          expect(PaperTrading::Reconciler).to have_received(:call).with(portfolio: portfolio)
        end
      end
    end

    context "when paper trading is disabled" do
      before do
        allow(Rails.configuration.x.paper_trading).to receive(:enabled).and_return(false)
      end

      it "returns early" do
        result = described_class.new.perform

        expect(result).to be_nil
        expect(PaperTrading::Reconciler).not_to have_received(:call)
      end
    end

    context "when job fails" do
      before do
        allow(Rails.configuration.x.paper_trading).to receive(:enabled).and_return(true)
        allow(PaperTrading::Portfolio).to receive(:find_or_create_default).and_raise(StandardError, "Error")
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it "sends error alert and raises" do
        expect do
          described_class.new.perform
        end.to raise_error(StandardError, "Error")

        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end
    end
  end
end
