# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationService, type: :service do
  let(:test_service) do
    Class.new(ApplicationService) do
      def call
        notify("Test message", tag: "TEST")
        typing_ping
        log_info("Info message")
        log_warn("Warning message")
        log_error("Error message")
        log_debug("Debug message")
      end
    end
  end

  describe ".call" do
    it "creates instance and calls call method" do
      allow_any_instance_of(test_service).to receive(:call).and_return(true)

      test_service.call

      expect_any_instance_of(test_service).to have_received(:call)
    end
  end

  describe "#notify" do
    context "when Telegram is enabled" do
      before do
        allow(TelegramNotifier).to receive(:enabled?).and_return(true)
        allow(TelegramNotifier).to receive(:send_message)
      end

      it "sends message with tag" do
        service = test_service.new
        service.send(:notify, "Test message", tag: "TEST")

        expect(TelegramNotifier).to have_received(:send_message)
      end

      it "sends message without tag" do
        service = test_service.new
        service.send(:notify, "Test message")

        expect(TelegramNotifier).to have_received(:send_message)
      end
    end

    context "when Telegram is disabled" do
      before do
        allow(TelegramNotifier).to receive(:enabled?).and_return(false)
      end

      it "does not send message" do
        service = test_service.new
        service.send(:notify, "Test message")

        expect(TelegramNotifier).not_to have_received(:send_message)
      end
    end

    context "when sending fails" do
      before do
        allow(TelegramNotifier).to receive(:enabled?).and_return(true)
        allow(TelegramNotifier).to receive(:send_message).and_raise(StandardError, "Error")
        allow(Rails.logger).to receive(:error)
      end

      it "logs error and continues" do
        service = test_service.new

        expect { service.send(:notify, "Test message") }.not_to raise_error
        expect(Rails.logger).to have_received(:error)
      end
    end
  end

  describe "#typing_ping" do
    context "when Telegram is enabled" do
      before do
        allow(TelegramNotifier).to receive(:enabled?).and_return(true)
        allow(TelegramNotifier).to receive(:send_chat_action)
      end

      it "sends typing action" do
        service = test_service.new
        service.send(:typing_ping)

        expect(TelegramNotifier).to have_received(:send_chat_action).with(action: "typing")
      end
    end

    context "when Telegram is disabled" do
      before do
        allow(TelegramNotifier).to receive(:enabled?).and_return(false)
      end

      it "does not send typing action" do
        service = test_service.new
        service.send(:typing_ping)

        expect(TelegramNotifier).not_to have_received(:send_chat_action)
      end
    end
  end

  describe "logging methods" do
    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:debug)
    end

    it "logs info messages" do
      service = test_service.new
      service.send(:log_info, "Info message")

      expect(Rails.logger).to have_received(:info)
    end

    it "logs warn messages" do
      service = test_service.new
      service.send(:log_warn, "Warning message")

      expect(Rails.logger).to have_received(:warn)
    end

    it "logs error messages" do
      service = test_service.new
      service.send(:log_error, "Error message")

      expect(Rails.logger).to have_received(:error)
    end

    it "logs debug messages" do
      service = test_service.new
      service.send(:log_debug, "Debug message")

      expect(Rails.logger).to have_received(:debug)
    end
  end
end
