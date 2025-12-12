# frozen_string_literal: true

require "rails_helper"

RSpec.describe MonitorJob do
  describe "#perform" do
    it "performs health checks" do
      # Create a test instrument for Dhan API check
      instrument = create(:instrument)

      # Mock LTP response
      allow(instrument).to receive(:ltp).and_return(100.0)

      result = described_class.perform_now

      expect(result).to be_a(Hash)
      expect(result).to have_key(:database)
      expect(result).to have_key(:dhan_api)
      expect(result).to have_key(:telegram)
      expect(result).to have_key(:candle_freshness)
    end
  end

  describe "#check_database" do
    it "checks database connection" do
      job = described_class.new
      result = job.send(:check_database)

      expect(result[:healthy]).to be true
      expect(result[:message]).to eq("OK")
    end
  end

  describe "#check_candle_freshness" do
    it "reports unhealthy when no candles exist" do
      result = described_class.new.send(:check_candle_freshness)
      expect(result[:healthy]).to be false
      expect(result[:message]).to include("No candles")
    end

    it "reports healthy when fresh candles exist" do
      instrument = create(:instrument)
      create(:candle_series_record, instrument: instrument, timestamp: Time.current)

      result = described_class.new.send(:check_candle_freshness)
      expect(result[:healthy]).to be true
    end
  end

  describe "#check_job_queue" do
    it "handles SolidQueue not installed gracefully" do
      job = described_class.new

      allow(job).to receive(:solid_queue_installed?).and_return(false)

      result = job.send(:check_job_queue)
      expect(result[:healthy]).to be true
      expect(result[:message]).to include("not installed")
    end

    it "checks job queue if SolidQueue installed" do
      # Skip if SolidQueue tables don't exist (common in test environment)
      unless ActiveRecord::Base.connection.table_exists?("solid_queue_jobs")
        skip "SolidQueue tables not available in test environment"
      end

      job = described_class.new
      allow(job).to receive(:solid_queue_installed?).and_return(true)

      # Mock SolidQueue models
      if defined?(SolidQueue::Job) && defined?(SolidQueue::FailedExecution) && defined?(SolidQueue::ClaimedExecution)
        # Create a proper double that avoids hitting the database
        pending_relation = double("pending_relation")
        allow(pending_relation).to receive_messages(count: 5, where: pending_relation)

        # Stub the class method chain to avoid database queries
        # The actual call is: SolidQueue::Job.where(...).where(...).count
        base_relation = double("base_relation")
        allow(SolidQueue::Job).to receive(:where).and_return(base_relation)
        allow(base_relation).to receive(:where).and_return(pending_relation)

        allow(SolidQueue::FailedExecution).to receive(:count).and_return(0)
        allow(SolidQueue::ClaimedExecution).to receive(:count).and_return(1)

        result = job.send(:check_job_queue)
        expect(result).to be_a(Hash)
        expect(result).to have_key(:healthy)
        expect(result).to have_key(:message)
      end
    end
  end
end
