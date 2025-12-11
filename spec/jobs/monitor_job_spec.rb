# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MonitorJob, type: :job do
  describe '#perform' do
    it 'performs health checks' do
      # Create a test instrument for Dhan API check
      instrument = create(:instrument)

      # Mock LTP response
      allow(instrument).to receive(:ltp).and_return(100.0)

      result = MonitorJob.perform_now

      expect(result).to be_a(Hash)
      expect(result).to have_key(:database)
      expect(result).to have_key(:dhan_api)
      expect(result).to have_key(:telegram)
      expect(result).to have_key(:candle_freshness)
    end
  end

  describe '#check_database' do
    it 'checks database connection' do
      job = MonitorJob.new
      result = job.send(:check_database)

      expect(result[:healthy]).to be true
      expect(result[:message]).to eq('OK')
    end
  end

  describe '#check_candle_freshness' do
    it 'reports unhealthy when no candles exist' do
      result = MonitorJob.new.send(:check_candle_freshness)
      expect(result[:healthy]).to be false
      expect(result[:message]).to include('No candles')
    end

    it 'reports healthy when fresh candles exist' do
      instrument = create(:instrument)
      create(:candle_series_record, instrument: instrument, timestamp: Time.current)

      result = MonitorJob.new.send(:check_candle_freshness)
      expect(result[:healthy]).to be true
    end
  end

  describe '#check_job_queue' do
    it 'handles SolidQueue not installed gracefully' do
      job = MonitorJob.new

      allow(job).to receive(:solid_queue_installed?).and_return(false)

      result = job.send(:check_job_queue)
      expect(result[:healthy]).to be true
      expect(result[:message]).to include('not installed')
    end

    it 'checks job queue if SolidQueue installed' do
      job = MonitorJob.new

      allow(job).to receive(:solid_queue_installed?).and_return(true)

      # Mock SolidQueue models if available
      if defined?(SolidQueue::Job)
        pending_relation = double('pending_relation', count: 5)
        allow(pending_relation).to receive(:where).and_return(pending_relation)
        allow(SolidQueue::Job).to receive(:where).and_return(pending_relation)

        if defined?(SolidQueue::FailedExecution) && defined?(SolidQueue::ClaimedExecution)
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
end

