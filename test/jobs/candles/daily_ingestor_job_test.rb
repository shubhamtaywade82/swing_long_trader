# frozen_string_literal: true

require 'test_helper'

module Candles
  class DailyIngestorJobTest < ActiveJob::TestCase
    test 'should enqueue job' do
      assert_enqueued_jobs 1 do
        DailyIngestorJob.perform_later
      end
    end

    test 'should call DailyIngestor service' do
      Candles::DailyIngestor.stub(:call, { processed: 10, errors: 0 }) do
        DailyIngestorJob.perform_now
      end
    end

    test 'should handle service errors' do
      Candles::DailyIngestor.stub(:call) { raise StandardError, 'API error' } do
        Telegram::Notifier.stub(:send_error_alert, nil) do
          assert_raises StandardError do
            DailyIngestorJob.perform_now
          end
        end
      end
    end
  end
end

