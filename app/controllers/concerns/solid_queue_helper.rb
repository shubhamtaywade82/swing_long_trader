# frozen_string_literal: true

module SolidQueueHelper
  extend ActiveSupport::Concern

  private

  def solid_queue_installed?
    defined?(SolidQueue) && ActiveRecord::Base.connection.table_exists?("solid_queue_jobs")
  end

  def check_solid_queue_status
    return { worker_running: false, pending: 0, running: 0, failed: 0 } unless solid_queue_installed?

    stats = get_solid_queue_stats

    # Check if worker is running by looking for recent activity
    # If there are running jobs or jobs finished recently, worker is likely running
    recent_activity = SolidQueue::Job
                      .where("finished_at > ?", 5.minutes.ago)
                      .exists?

    # Also check if there are claimed executions (jobs being processed)
    has_claimed = SolidQueue::ClaimedExecution.exists?

    {
      worker_running: recent_activity || has_claimed || stats[:running] > 0,
      pending: stats[:pending],
      running: stats[:running],
      failed: stats[:failed],
      recent_activity: recent_activity,
    }
  rescue StandardError => e
    Rails.logger.error("Error checking SolidQueue status: #{e.message}")
    { worker_running: false, pending: 0, running: 0, failed: 0, error: e.message }
  end

  def get_solid_queue_stats
    return { pending: 0, running: 0, failed: 0 } unless solid_queue_installed?

    {
      pending: SolidQueue::Job.where(finished_at: nil)
                              .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
                              .count,
      running: SolidQueue::ClaimedExecution.count,
      failed: SolidQueue::FailedExecution.count,
    }
  rescue StandardError => e
    Rails.logger.error("Error getting SolidQueue stats: #{e.message}")
    { pending: 0, running: 0, failed: 0 }
  end
end
