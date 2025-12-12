# frozen_string_literal: true

require "rails_helper"

RSpec.describe Candles::WeeklyIngestorJob do
  let(:instrument) { create(:instrument) }

  describe "#perform" do
    context "when ingestion succeeds" do
      before do
        allow(Candles::WeeklyIngestor).to receive(:call).and_return(
          {
            processed: 1,
            success: 1,
            failed: 0,
            total_candles: 5,
          },
        )
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it "calls WeeklyIngestor service" do
        result = described_class.new.perform(instruments: Instrument.where(id: instrument.id))

        expect(result[:success]).to eq(1)
        expect(Candles::WeeklyIngestor).to have_received(:call)
      end

      it "logs success message" do
        allow(Rails.logger).to receive(:info)

        described_class.new.perform(instruments: Instrument.where(id: instrument.id))

        expect(Rails.logger).to have_received(:info)
      end
    end

    context "when no candles ingested" do
      before do
        allow(Candles::WeeklyIngestor).to receive(:call).and_return(
          {
            processed: 0,
            success: 0,
            failed: 0,
            total_candles: 0,
          },
        )
      end

      it "logs warning" do
        allow(Rails.logger).to receive(:warn)

        described_class.new.perform

        expect(Rails.logger).to have_received(:warn)
      end
    end

    context "when ingestion fails" do
      before do
        allow(Candles::WeeklyIngestor).to receive(:call).and_raise(StandardError, "Ingestion error")
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it "sends error alert and raises" do
        expect do
          described_class.new.perform
        end.to raise_error(StandardError, "Ingestion error")

        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end
    end
  end
end
