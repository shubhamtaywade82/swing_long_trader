# frozen_string_literal: true

module Admin
  class SolidQueueController < ApplicationController
    before_action :authenticate_user! # Adjust based on your auth setup

    def index
      @jobs_by_status = {
        pending: SolidQueue::Job.where(finished_at: nil)
                                 .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
                                 .count,
        running: SolidQueue::ClaimedExecution.count,
        failed: SolidQueue::FailedExecution.count,
        finished: SolidQueue::Job.where.not(finished_at: nil)
                                  .where("finished_at > ?", 24.hours.ago)
                                  .count,
      }

      @jobs_by_queue = SolidQueue::Job
                       .where(finished_at: nil)
                       .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
                       .group(:queue_name)
                       .count

      @recent_failures = SolidQueue::FailedExecution
                        .includes(:job)
                        .order(created_at: :desc)
                        .limit(20)

      @recent_jobs = SolidQueue::Job
                     .order(created_at: :desc)
                     .limit(50)

      @queue_stats = calculate_queue_stats
    end

    def show
      @job = SolidQueue::Job.find(params[:id])
      @execution = @job.executions.order(created_at: :desc).first
      @failed_execution = @job.failed_executions.order(created_at: :desc).first
    end

    def retry_failed
      failed_execution = SolidQueue::FailedExecution.find(params[:id])
      job = failed_execution.job

      # Re-enqueue the job
      job_class = job.class_name.constantize
      job_class.perform_later(*job.arguments)

      # Mark failed execution as retried
      failed_execution.update!(retried_at: Time.current)

      redirect_to admin_solid_queue_path, notice: "Job re-enqueued successfully"
    rescue StandardError => e
      redirect_to admin_solid_queue_path, alert: "Failed to retry job: #{e.message}"
    end

    def clear_finished
      count = SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)
      redirect_to admin_solid_queue_path, notice: "Cleared #{count} finished jobs"
    rescue StandardError => e
      redirect_to admin_solid_queue_path, alert: "Failed to clear jobs: #{e.message}"
    end

    private

    def calculate_queue_stats
      queues = SolidQueue::Job.distinct.pluck(:queue_name)
      stats = {}

      queues.each do |queue_name|
        jobs = SolidQueue::Job.where(queue_name: queue_name)
        stats[queue_name] = {
          pending: jobs.where(finished_at: nil)
                       .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
                       .count,
          running: jobs.joins(:claimed_executions).count,
          failed: jobs.joins(:failed_executions).count,
          avg_duration: calculate_avg_duration(jobs),
        }
      end

      stats
    end

    def calculate_avg_duration(jobs)
      completed = jobs.where.not(finished_at: nil)
                      .where.not(created_at: nil)
                      .where("finished_at > ?", 24.hours.ago)
                      .limit(100)

      return 0 if completed.empty?

      durations = completed.filter_map do |job|
        next unless job.created_at && job.finished_at

        (job.finished_at - job.created_at).to_f
      end

      return 0 if durations.empty?

      (durations.sum / durations.size).round(2)
    end
  end
end
