# frozen_string_literal: true

require 'test_helper'

class ApplicationJobTest < ActiveJob::TestCase
  # Test job enqueueing
  test 'should enqueue job' do
    assert_enqueued_jobs 1 do
      MonitorJob.perform_later
    end
  end

  test 'should execute job' do
    instrument = create(:instrument)
    instrument.stub(:ltp, 100.0) do
      assert_performed_jobs 1 do
        MonitorJob.perform_later
      end
    end
  end

  test 'should handle job errors' do
    # Create a job that will fail
    failing_job = Class.new(ApplicationJob) do
      def perform
        raise StandardError, 'Test error'
      end
    end

    # Mock Telegram notifier to avoid actual API calls
    Telegram::Notifier.stub(:send_error_alert, nil) do
      assert_raises StandardError do
        failing_job.perform_now
      end
    end
  end

  test 'should track job duration' do
    instrument = create(:instrument)
    instrument.stub(:ltp, 100.0) do
      Metrics::Tracker.stub(:track_job_duration, nil) do
        MonitorJob.perform_now
      end
    end
  end
end

