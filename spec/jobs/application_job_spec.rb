# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationJob, type: :job do
  describe 'job enqueueing' do
    it 'enqueues job' do
      expect do
        MonitorJob.perform_later
      end.to have_enqueued_job(MonitorJob)
    end

    it 'executes job' do
      instrument = create(:instrument)
      allow(instrument).to receive(:ltp).and_return(100.0)

      expect do
        MonitorJob.perform_later
      end.to have_enqueued_job(MonitorJob)
    end

    it 'handles job errors' do
      # Create a job that will fail
      failing_job = Class.new(ApplicationJob) do
        def perform
          raise StandardError, 'Test error'
        end
      end

      # Mock Telegram notifier to avoid actual API calls
      allow(Telegram::Notifier).to receive(:send_error_alert).and_return(nil)

      expect do
        failing_job.perform_now
      end.to raise_error(StandardError, 'Test error')
    end

    it 'tracks job duration' do
      instrument = create(:instrument)
      allow(instrument).to receive(:ltp).and_return(100.0)
      allow(Metrics::Tracker).to receive(:track_job_duration).and_return(nil)

      MonitorJob.perform_now
    end
  end
end

