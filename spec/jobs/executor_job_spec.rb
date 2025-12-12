# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExecutorJob do
  let(:signal) do
    {
      symbol: "RELIANCE",
      direction: :long,
      entry_price: 2500.0,
      qty: 10,
      instrument_id: 1,
    }
  end

  before do
    allow(Strategies::Swing::Executor).to receive(:call).and_return(
      { success: true, order: double("Order", id: 1) },
    )
    allow(AlgoConfig).to receive(:fetch).and_return(false)
    allow(Telegram::Notifier).to receive(:send_signal_alert)
    allow(Telegram::Notifier).to receive(:send_error_alert)
  end

  describe "#perform" do
    it "executes order via Swing::Executor" do
      described_class.new.perform(signal)

      expect(Strategies::Swing::Executor).to have_received(:call).with(
        hash_including(symbol: "RELIANCE", direction: :long),
        hash_including(dry_run: nil),
      )
    end

    it "sends notification for successful live trade" do
      allow(AlgoConfig).to receive(:fetch).with(%i[notifications telegram notify_entry]).and_return(true)
      allow(Strategies::Swing::Executor).to receive(:call).and_return(
        { success: true, order: double("Order", id: 1), paper_trade: false },
      )

      described_class.new.perform(signal)

      expect(Telegram::Notifier).to have_received(:send_signal_alert)
    end

    it "does not send notification for paper trades" do
      allow(Strategies::Swing::Executor).to receive(:call).and_return(
        { success: true, paper_trade: true },
      )

      described_class.new.perform(signal)

      expect(Telegram::Notifier).not_to have_received(:send_signal_alert)
    end

    it "handles execution failure gracefully" do
      allow(Strategies::Swing::Executor).to receive(:call).and_return(
        { success: false, error: "Insufficient funds" },
      )

      result = described_class.new.perform(signal)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Insufficient funds")
    end

    it "handles exceptions" do
      allow(Strategies::Swing::Executor).to receive(:call).and_raise(StandardError.new("API error"))

      expect do
        described_class.new.perform(signal)
      end.to raise_error(StandardError)

      expect(Telegram::Notifier).to have_received(:send_error_alert)
    end

    it "normalizes signal hash with string keys" do
      signal_with_strings = {
        "symbol" => "RELIANCE",
        "direction" => "long",
        "entry_price" => 2500.0,
        "qty" => 10,
      }

      described_class.new.perform(signal_with_strings)

      expect(Strategies::Swing::Executor).to have_received(:call).with(
        hash_including(symbol: "RELIANCE", direction: :long),
        anything,
      )
    end
  end
end
