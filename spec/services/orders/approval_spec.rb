# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::Approval do
  let(:order) { create(:order, status: "pending", requires_approval: true) }
  let(:instrument) { create(:instrument) }

  before do
    allow(Orders::ProcessApprovedJob).to receive(:perform_later)
    allow(Telegram::Notifier).to receive(:send_error_alert)
  end

  describe ".approve" do
    it "approves an order" do
      result = described_class.approve(order.id, approved_by: "admin")

      expect(result[:success]).to be true
      order.reload
      expect(order.approved_at).to be_present
      expect(order.approved_by).to eq("admin")
    end

    it "enqueues ProcessApprovedJob" do
      described_class.approve(order.id)

      expect(Orders::ProcessApprovedJob).to have_received(:perform_later).with(order_id: order.id)
    end

    it "sends notification" do
      described_class.approve(order.id)

      expect(Telegram::Notifier).to have_received(:send_error_alert)
    end

    it "returns error if order not found" do
      result = described_class.approve(999_999)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Order not found")
    end

    it "returns error if order does not require approval" do
      order.update!(requires_approval: false)
      result = described_class.approve(order.id)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Order does not require approval")
    end

    it "returns error if order already processed" do
      order.update!(approved_at: Time.current)
      result = described_class.approve(order.id)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Order already processed")
    end
  end

  describe ".reject" do
    it "rejects an order" do
      result = described_class.reject(order.id, reason: "Risk too high", rejected_by: "admin")

      expect(result[:success]).to be true
      order.reload
      expect(order.rejected_at).to be_present
      expect(order.rejected_by).to eq("admin")
      expect(order.rejection_reason).to eq("Risk too high")
      expect(order.status).to eq("cancelled")
    end

    it "sends notification" do
      described_class.reject(order.id, reason: "Test")

      expect(Telegram::Notifier).to have_received(:send_error_alert)
    end

    it "returns error if order not found" do
      result = described_class.reject(999_999)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Order not found")
    end

    it "returns error if order already rejected" do
      order.update!(rejected_at: Time.current)
      result = described_class.reject(order.id)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Order already processed")
    end

    it "handles missing rejection reason" do
      result = described_class.reject(order.id, rejected_by: "admin")

      expect(result[:success]).to be true
      order.reload
      expect(order.rejection_reason).to be_nil
    end
  end

  describe "error handling" do
    context "when approval fails" do
      before do
        allow_any_instance_of(Order).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(Order.new))
        allow(Rails.logger).to receive(:error)
      end

      it "handles update failure gracefully" do
        result = described_class.approve(order.id)

        expect(result[:success]).to be false
        expect(Rails.logger).to have_received(:error)
      end
    end

    context "when rejection fails" do
      before do
        allow_any_instance_of(Order).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(Order.new))
        allow(Rails.logger).to receive(:error)
      end

      it "handles update failure gracefully" do
        result = described_class.reject(order.id)

        expect(result[:success]).to be false
        expect(Rails.logger).to have_received(:error)
      end
    end

    context "when notification fails" do
      before do
        allow(Telegram::Notifier).to receive(:send_error_alert).and_raise(StandardError, "Notification failed")
        allow(Rails.logger).to receive(:error)
      end

      it "handles notification failure gracefully" do
        result = described_class.approve(order.id)

        expect(result[:success]).to be true
        expect(Rails.logger).to have_received(:error)
      end
    end
  end

  describe "invalid action" do
    it "returns error for invalid action" do
      service = described_class.new(order_id: order.id, action: :invalid)
      result = service.call

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Invalid action")
    end
  end

  describe "metadata updates" do
    it "updates metadata on approval" do
      result = described_class.approve(order.id, approved_by: "admin")

      expect(result[:success]).to be true
      order.reload
      metadata = JSON.parse(order.metadata)
      expect(metadata["approved_at"]).to be_present
      expect(metadata["approved_by"]).to eq("admin")
    end

    it "updates metadata on rejection" do
      result = described_class.reject(order.id, reason: "Test", rejected_by: "admin")

      expect(result[:success]).to be true
      order.reload
      metadata = JSON.parse(order.metadata)
      expect(metadata["rejected_at"]).to be_present
      expect(metadata["rejected_by"]).to eq("admin")
      expect(metadata["rejection_reason"]).to eq("Test")
    end

    it "preserves existing metadata when updating" do
      order.update!(metadata: { existing_key: "value" }.to_json)
      result = described_class.approve(order.id, approved_by: "admin")

      expect(result[:success]).to be true
      order.reload
      metadata = JSON.parse(order.metadata)
      expect(metadata["existing_key"]).to eq("value")
      expect(metadata["approved_at"]).to be_present
    end
  end

  describe "#send_approval_notification" do
    it "sends notification with order details" do
      allow(Telegram::Notifier).to receive(:send_error_alert)
      service = described_class.new(order_id: order.id, action: :approve, approved_by: "admin")
      service.call

      expect(Telegram::Notifier).to have_received(:send_error_alert) do |message, options|
        expect(message).to include("Order Approved")
        expect(message).to include(order.symbol)
        expect(message).to include(order.transaction_type)
        expect(message).to include(order.quantity.to_s)
        expect(options[:context]).to eq("Order Approval")
      end
    end

    it "handles notification failure gracefully" do
      allow(Telegram::Notifier).to receive(:send_error_alert).and_raise(StandardError, "Telegram error")
      allow(Rails.logger).to receive(:error)

      result = described_class.approve(order.id)

      expect(result[:success]).to be true
      expect(Rails.logger).to have_received(:error).with(/Failed to send approval notification/)
    end
  end

  describe "#send_rejection_notification" do
    it "sends notification with rejection details" do
      allow(Telegram::Notifier).to receive(:send_error_alert)
      service = described_class.new(order_id: order.id, action: :reject, rejected_by: "admin", reason: "Risk too high")
      service.call

      expect(Telegram::Notifier).to have_received(:send_error_alert) do |message, options|
        expect(message).to include("Order Rejected")
        expect(message).to include(order.symbol)
        expect(message).to include("Risk too high")
        expect(options[:context]).to eq("Order Rejection")
      end
    end

    it "handles missing rejection reason in notification" do
      allow(Telegram::Notifier).to receive(:send_error_alert)
      service = described_class.new(order_id: order.id, action: :reject, rejected_by: "admin")
      service.call

      expect(Telegram::Notifier).to have_received(:send_error_alert) do |message, _|
        expect(message).to include("Not specified")
      end
    end

    it "handles notification failure gracefully" do
      allow(Telegram::Notifier).to receive(:send_error_alert).and_raise(StandardError, "Telegram error")
      allow(Rails.logger).to receive(:error)

      result = described_class.reject(order.id, reason: "Test")

      expect(result[:success]).to be true
      expect(Rails.logger).to have_received(:error).with(/Failed to send rejection notification/)
    end
  end

  describe "#update_metadata" do
    it "merges new data with existing metadata" do
      order.update!(metadata: { key1: "value1" }.to_json)
      service = described_class.new(order_id: order.id, action: :approve, approved_by: "admin")
      service.call

      order.reload
      metadata = JSON.parse(order.metadata)
      expect(metadata["key1"]).to eq("value1")
      expect(metadata["approved_at"]).to be_present
    end

    it "handles nil metadata" do
      order.update!(metadata: nil)
      service = described_class.new(order_id: order.id, action: :approve, approved_by: "admin")
      service.call

      order.reload
      metadata = JSON.parse(order.metadata)
      expect(metadata["approved_at"]).to be_present
    end
  end
end
