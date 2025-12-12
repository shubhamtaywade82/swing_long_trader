# frozen_string_literal: true

require "rails_helper"

RSpec.describe JobLogging, type: :concern do
  # Create a test job class that includes JobLogging
  let(:test_job_class) do
    Class.new(ApplicationJob) do
      include JobLogging

      def perform
        "success"
      end
    end
  end

  before do
    allow(Metrics::Tracker).to receive(:track_job_duration)
    allow(Metrics::Tracker).to receive(:track_failed_job)
    allow(Telegram::Notifier).to receive(:send_error_alert)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe "#track_job_execution" do
    it "tracks job duration" do
      job = test_job_class.new
      job.perform_now

      expect(Metrics::Tracker).to have_received(:track_job_duration).with(
        test_job_class.name,
        a_value > 0,
      )
    end

    it "logs job start" do
      job = test_job_class.new
      job.perform_now

      expect(Rails.logger).to have_received(:info).with(/Starting execution/)
    end

    it "logs job completion" do
      job = test_job_class.new
      job.perform_now

      expect(Rails.logger).to have_received(:info).with(/Completed in/)
    end

    it "logs error and duration when job fails" do
      failing_job_class = Class.new(ApplicationJob) do
        include JobLogging

        def perform
          raise StandardError, "Job failed"
        end
      end

      job = failing_job_class.new

      expect do
        job.perform_now
      end.to raise_error(StandardError, "Job failed")

      expect(Rails.logger).to have_received(:error).with(/Failed after/)
    end
  end

  describe "#handle_job_error" do
    it "tracks failed job" do
      failing_job_class = Class.new(ApplicationJob) do
        include JobLogging

        def perform
          raise StandardError, "Job failed"
        end
      end

      job = failing_job_class.new

      expect do
        job.perform_now
      end.to raise_error(StandardError)

      expect(Metrics::Tracker).to have_received(:track_failed_job).with(failing_job_class.name)
    end

    it "logs error details" do
      failing_job_class = Class.new(ApplicationJob) do
        include JobLogging

        def perform
          raise StandardError, "Job failed"
        end
      end

      job = failing_job_class.new

      expect do
        job.perform_now
      end.to raise_error(StandardError)

      expect(Rails.logger).to have_received(:error).with(/Error: StandardError - Job failed/)
      expect(Rails.logger).to have_received(:error).with(/Backtrace:/)
    end

    it "sends error alert to Telegram" do
      failing_job_class = Class.new(ApplicationJob) do
        include JobLogging

        def perform
          raise StandardError, "Job failed"
        end
      end

      job = failing_job_class.new

      expect do
        job.perform_now
      end.to raise_error(StandardError)

      expect(Telegram::Notifier).to have_received(:send_error_alert).with(
        /Job failed: #{failing_job_class.name}/,
        context: failing_job_class.name,
      )
    end

    it "re-raises the error" do
      failing_job_class = Class.new(ApplicationJob) do
        include JobLogging

        def perform
          raise StandardError, "Job failed"
        end
      end

      job = failing_job_class.new

      expect do
        job.perform_now
      end.to raise_error(StandardError, "Job failed")
    end
  end
end
