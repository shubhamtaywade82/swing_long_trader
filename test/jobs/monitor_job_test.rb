# frozen_string_literal: true

require 'test_helper'

class MonitorJobTest < ActiveJob::TestCase
  test 'should perform health checks' do
    # Create a test instrument for Dhan API check
    instrument = create(:instrument)

    # Mock LTP response
    instrument.stub(:ltp, 100.0) do
      result = MonitorJob.perform_now

      assert_kind_of Hash, result
      assert result.key?(:database)
      assert result.key?(:dhan_api)
      assert result.key?(:telegram)
      assert result.key?(:candle_freshness)
    end
  end

  test 'should check database connection' do
    job = MonitorJob.new
    result = job.send(:check_database)

    assert result[:healthy]
    assert_equal 'OK', result[:message]
  end

  test 'should check candle freshness' do
    # No candles
    result = MonitorJob.new.send(:check_candle_freshness)
    assert_not result[:healthy]
    assert_includes result[:message], 'No candles'

    # Fresh candles
    instrument = create(:instrument)
    create(:candle_series_record, instrument: instrument, timestamp: Time.current)

    result = MonitorJob.new.send(:check_candle_freshness)
    assert result[:healthy]
  end

  test 'should check job queue if SolidQueue installed' do
    job = MonitorJob.new

    # Mock table existence check
    job.stub(:solid_queue_installed?, true) do
      # Mock SolidQueue models - this test verifies the method structure
      # Actual SolidQueue integration tested in integration tests
      begin
        # Stub ActiveRecord queries
        pending_relation = mock('pending_relation')
        pending_relation.stub(:count, 5)
        pending_relation.stub(:where, pending_relation)

        if defined?(SolidQueue::Job)
          SolidQueue::Job.stub(:where, pending_relation) do
            if defined?(SolidQueue::FailedExecution) && defined?(SolidQueue::ClaimedExecution)
              SolidQueue::FailedExecution.stub(:count, 0) do
                SolidQueue::ClaimedExecution.stub(:count, 1) do
                  result = job.send(:check_job_queue)
                  assert_kind_of Hash, result
                  assert result.key?(:healthy)
                  assert result.key?(:message)
                end
              end
            else
              skip 'SolidQueue models not available'
            end
          end
        else
          skip 'SolidQueue not available'
        end
      rescue NameError, LoadError
        skip 'SolidQueue not available'
      end
    end
  end

  test 'should handle SolidQueue not installed gracefully' do
    job = MonitorJob.new

    job.stub(:solid_queue_installed?, false) do
      result = job.send(:check_job_queue)
      assert result[:healthy]
      assert_includes result[:message], 'not installed'
    end
  end
end

