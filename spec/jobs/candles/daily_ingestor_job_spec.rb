# frozen_string_literal: true

require "rails_helper"

RSpec.describe Candles::DailyIngestorJob do
  describe "job execution" do
    it "enqueues job" do
      expect do
        described_class.perform_later
      end.to have_enqueued_job(described_class)
    end

    it "calls DailyIngestor service" do
      allow(Candles::DailyIngestor).to receive(:call).and_return({
        processed: 10,
        success: 8,
        failed: 2,
        total_candles: 100,
        errors: [],
      })

      described_class.perform_now
    end

    it "handles service errors" do
      allow(Candles::DailyIngestor).to receive(:call).and_raise(StandardError, "API error")
      allow(Telegram::Notifier).to receive(:send_error_alert).and_return(nil)

      expect do
        described_class.perform_now
      end.to raise_error(StandardError, "API error")
    end
  end
end
