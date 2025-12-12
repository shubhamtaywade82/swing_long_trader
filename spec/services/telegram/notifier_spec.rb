# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telegram::Notifier, type: :service do
  let(:signal) do
    {
      symbol: "RELIANCE",
      direction: "long",
      entry_price: 100.0,
      confidence: 75,
    }
  end

  before do
    allow(TelegramNotifier).to receive(:enabled?).and_return(true)
    allow(TelegramNotifier).to receive(:send_message)
    allow(Telegram::AlertFormatter).to receive_messages(format_signal_alert: "Formatted message", format_daily_candidates: "Formatted candidates", format_exit_alert: "Formatted exit", format_portfolio_snapshot: "Formatted portfolio", format_error_alert: "Formatted error")
  end

  describe ".send_signal_alert" do
    it "delegates to instance method" do
      instance = described_class.new
      allow(instance).to receive(:send_signal_alert).and_return(true)
      allow(described_class).to receive(:new).and_return(instance)

      described_class.send_signal_alert(signal)

      expect(instance).to have_received(:send_signal_alert)
    end
  end

  describe "#send_signal_alert" do
    it "sends formatted signal alert" do
      described_class.new.send_signal_alert(signal)

      expect(Telegram::AlertFormatter).to have_received(:format_signal_alert).with(signal)
      expect(TelegramNotifier).to have_received(:send_message)
    end

    context "when Telegram is disabled" do
      before do
        allow(TelegramNotifier).to receive(:enabled?).and_return(false)
      end

      it "does not send message" do
        described_class.new.send_signal_alert(signal)

        expect(TelegramNotifier).not_to have_received(:send_message)
      end
    end

    context "when formatting fails" do
      before do
        allow(Telegram::AlertFormatter).to receive(:format_signal_alert).and_raise(StandardError, "Error")
        allow(Rails.logger).to receive(:error)
      end

      it "logs error and continues" do
        expect { described_class.new.send_signal_alert(signal) }.not_to raise_error
        expect(Rails.logger).to have_received(:error)
      end
    end
  end

  describe "#send_daily_candidates" do
    let(:candidates) { [{ symbol: "RELIANCE", score: 85 }] }

    it "sends formatted candidates" do
      described_class.new.send_daily_candidates(candidates)

      expect(Telegram::AlertFormatter).to have_received(:format_daily_candidates).with(candidates)
      expect(TelegramNotifier).to have_received(:send_message)
    end
  end

  describe "#send_exit_alert" do
    it "sends formatted exit alert" do
      described_class.new.send_exit_alert(
        signal,
        exit_reason: "tp_hit",
        exit_price: 110.0,
        pnl: 100.0,
      )

      expect(Telegram::AlertFormatter).to have_received(:format_exit_alert)
      expect(TelegramNotifier).to have_received(:send_message)
    end
  end

  describe "#send_portfolio_snapshot" do
    let(:portfolio_data) { { equity: 100_000, pnl: 5000 } }

    it "sends formatted portfolio snapshot" do
      described_class.new.send_portfolio_snapshot(portfolio_data)

      expect(Telegram::AlertFormatter).to have_received(:format_portfolio_snapshot).with(portfolio_data)
      expect(TelegramNotifier).to have_received(:send_message)
    end
  end

  describe "#send_error_alert" do
    it "sends formatted error alert" do
      described_class.new.send_error_alert("Error message", context: "Test")

      expect(Telegram::AlertFormatter).to have_received(:format_error_alert).with("Error message", context: "Test")
      expect(TelegramNotifier).to have_received(:send_message)
    end
  end
end
