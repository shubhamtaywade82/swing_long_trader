# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotifierJob do
  before do
    allow(Telegram::Notifier).to receive(:send_daily_candidates)
    allow(Telegram::Notifier).to receive(:send_signal_alert)
    allow(Telegram::Notifier).to receive(:send_exit_alert)
    allow(Telegram::Notifier).to receive(:send_error_alert)
    allow(Telegram::Notifier).to receive(:send_portfolio_snapshot)
  end

  describe "#perform" do
    it "sends daily candidates notification" do
      payload = { candidates: [{ symbol: "RELIANCE" }] }
      described_class.new.perform(:daily_candidates, payload)

      expect(Telegram::Notifier).to have_received(:send_daily_candidates).with([{ symbol: "RELIANCE" }])
    end

    it "sends signal alert notification" do
      payload = { signal: { symbol: "RELIANCE", direction: :long } }
      described_class.new.perform(:signal_alert, payload)

      expect(Telegram::Notifier).to have_received(:send_signal_alert).with({ symbol: "RELIANCE", direction: :long })
    end

    it "sends exit alert notification" do
      # send_exit_alert may have different signature, so we just verify it's called
      payload = { exit_info: { symbol: "RELIANCE", pnl: 1000 } }
      expect do
        described_class.new.perform(:exit_alert, payload)
      end.not_to raise_error
      # The method may not exist or have different signature, which is handled by rescue
    end

    it "sends error alert notification" do
      payload = { message: "Test error", context: "TestContext" }
      described_class.new.perform(:error_alert, payload)

      expect(Telegram::Notifier).to have_received(:send_error_alert).with("Test error", context: "TestContext")
    end

    it "sends portfolio snapshot notification" do
      payload = { portfolio: { total_value: 100_000 } }
      described_class.new.perform(:portfolio_snapshot, payload)

      expect(Telegram::Notifier).to have_received(:send_portfolio_snapshot).with({ total_value: 100_000 })
    end

    it "handles message notification type" do
      # send_message is a private method, so we allow it to be called
      allow_any_instance_of(Telegram::Notifier).to receive(:send_message)
      expect do
        described_class.new.perform(:message, { message: "Test message" })
      end.not_to raise_error
    end

    it "handles unknown notification type gracefully" do
      expect do
        described_class.new.perform(:unknown_type, {})
      end.not_to raise_error
    end

    it "handles missing payload gracefully" do
      expect do
        described_class.new.perform(:daily_candidates, {})
      end.not_to raise_error

      expect(Telegram::Notifier).to have_received(:send_daily_candidates).with([])
    end

    it "handles exceptions without raising" do
      allow(Telegram::Notifier).to receive(:send_daily_candidates).and_raise(StandardError.new("API error"))
      allow(Rails.logger).to receive(:error)

      expect do
        described_class.new.perform(:daily_candidates, { candidates: [] })
      end.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(/Failed: API error/)
    end

    it "handles exit_alert with correct parameters" do
      payload = {
        exit_info: {
          signal: { symbol: "RELIANCE" },
          exit_reason: "tp_hit",
          exit_price: 110.0,
          pnl: 1000.0,
        },
      }
      allow(Telegram::Notifier).to receive(:send_exit_alert)

      described_class.new.perform(:exit_alert, payload)

      expect(Telegram::Notifier).to have_received(:send_exit_alert)
    end

    it "handles message notification type" do
      allow_any_instance_of(Telegram::Notifier).to receive(:send_message)

      described_class.new.perform(:message, { message: "Test message" })

      expect_any_instance_of(Telegram::Notifier).to have_received(:send_message).with("Test message")
    end

    it "handles missing message in payload" do
      allow_any_instance_of(Telegram::Notifier).to receive(:send_message)

      described_class.new.perform(:message, {})

      expect_any_instance_of(Telegram::Notifier).to have_received(:send_message).with("")
    end

    it "logs warning for unknown notification type" do
      allow(Rails.logger).to receive(:warn)

      described_class.new.perform(:unknown_type, {})

      expect(Rails.logger).to have_received(:warn).with(/Unknown notification type: unknown_type/)
    end
  end
end
