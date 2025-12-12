# frozen_string_literal: true

require "rails_helper"

RSpec.describe Screeners::SwingScreenerJob do
  let(:candidates) do
    [
      { instrument_id: 1, symbol: "STOCK1", score: 85.0 },
      { instrument_id: 2, symbol: "STOCK2", score: 82.0 },
    ]
  end

  before do
    allow(Screeners::SwingScreener).to receive(:call).and_return(candidates)
    allow(Telegram::Notifier).to receive(:send_daily_candidates)
    allow(Telegram::Notifier).to receive(:send_error_alert)
    allow(Strategies::Swing::AnalysisJob).to receive(:perform_later)
    allow(AlgoConfig).to receive(:fetch).and_return(false)
  end

  describe "#perform" do
    it "calls SwingScreener with provided instruments" do
      instruments = Instrument.where(id: [1, 2])
      described_class.new.perform(instruments: instruments, limit: 10)

      expect(Screeners::SwingScreener).to have_received(:call).with(instruments: instruments, limit: 10)
    end

    it "uses default parameters when none provided" do
      described_class.new.perform

      expect(Screeners::SwingScreener).to have_received(:call).with(instruments: nil, limit: nil)
    end

    it "sends top 10 candidates to Telegram when enabled" do
      allow(AlgoConfig).to receive(:fetch).with(%i[notifications telegram notify_screener_results]).and_return(true)

      described_class.new.perform

      expect(Telegram::Notifier).to have_received(:send_daily_candidates).with(candidates.first(10))
    end

    it "does not send notification when disabled" do
      allow(AlgoConfig).to receive(:fetch).with(%i[notifications telegram notify_screener_results]).and_return(false)

      described_class.new.perform

      expect(Telegram::Notifier).not_to have_received(:send_daily_candidates)
    end

    it "triggers analysis job when auto_analyze is enabled" do
      allow(AlgoConfig).to receive(:fetch).with(%i[swing_trading strategy auto_analyze]).and_return(true)

      described_class.new.perform

      expect(Strategies::Swing::AnalysisJob).to have_received(:perform_later).with([1, 2])
    end

    it "triggers analysis for top 20 candidates" do
      many_candidates = (1..30).map { |i| { instrument_id: i, symbol: "STOCK#{i}", score: 100.0 - i } }
      allow(Screeners::SwingScreener).to receive(:call).and_return(many_candidates)
      allow(AlgoConfig).to receive(:fetch).with(%i[swing_trading strategy auto_analyze]).and_return(true)

      described_class.new.perform

      expected_ids = (1..20).to_a
      expect(Strategies::Swing::AnalysisJob).to have_received(:perform_later).with(expected_ids)
    end

    it "does not trigger analysis when auto_analyze is disabled" do
      allow(AlgoConfig).to receive(:fetch).with(%i[swing_trading strategy auto_analyze]).and_return(false)

      described_class.new.perform

      expect(Strategies::Swing::AnalysisJob).not_to have_received(:perform_later)
    end

    it "does not trigger analysis when no candidates" do
      allow(Screeners::SwingScreener).to receive(:call).and_return([])
      allow(AlgoConfig).to receive(:fetch).with(%i[swing_trading strategy auto_analyze]).and_return(true)

      described_class.new.perform

      expect(Strategies::Swing::AnalysisJob).not_to have_received(:perform_later)
    end

    it "returns candidates" do
      result = described_class.new.perform

      expect(result).to eq(candidates)
    end

    it "logs candidate count" do
      allow(Rails.logger).to receive(:info)

      described_class.new.perform

      expect(Rails.logger).to have_received(:info).with(/Found 2 candidates/)
    end

    it "logs when triggering analysis job" do
      allow(AlgoConfig).to receive(:fetch).with(%i[swing_trading strategy auto_analyze]).and_return(true)
      allow(Rails.logger).to receive(:info)

      described_class.new.perform

      expect(Rails.logger).to have_received(:info).with(/Triggered analysis job/)
    end

    context "when error occurs" do
      before do
        allow(Screeners::SwingScreener).to receive(:call).and_raise(StandardError, "Screener error")
        allow(Rails.logger).to receive(:error)
      end

      it "logs error" do
        expect do
          described_class.new.perform
        end.to raise_error(StandardError, "Screener error")

        expect(Rails.logger).to have_received(:error).with(/Failed: Screener error/)
      end

      it "sends error alert to Telegram" do
        expect do
          described_class.new.perform
        end.to raise_error(StandardError)

        expect(Telegram::Notifier).to have_received(:send_error_alert).with(
          /Swing screener failed: Screener error/,
          context: "SwingScreenerJob",
        )
      end
    end
  end
end
