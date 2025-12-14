# frozen_string_literal: true

module Admin
  class SolidQueueController < ApplicationController
    # No authentication required - public admin interface

    PER_PAGE = 25

    def index
      @filter_status = params[:status] || "all"
      @filter_queue = params[:queue].presence
      @filter_class = params[:class_name].presence
      @search_term = params[:search].presence
      @show_finished_successful = params[:show_finished_successful] == "true"
      @page = [params[:page].to_i, 1].max

      # OPTIMIZE: Use single query with conditional counts
      base_jobs = SolidQueue::Job.all
      @jobs_by_status = calculate_job_status_counts(base_jobs)

      # OPTIMIZE: Cache queue counts
      @jobs_by_queue = SolidQueue::Job
                       .where(finished_at: nil)
                       .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
                       .group(:queue_name)
                       .count

      # OPTIMIZE: Limit failures for compact display
      @recent_failures = SolidQueue::FailedExecution
                         .includes(:job)
                         .order(created_at: :desc)
                         .limit(10)

      # OPTIMIZE: Paginated jobs with efficient counting
      jobs_relation = filter_jobs
      # Use efficient count - limit for very large unfiltered datasets
      @total_count = if @filter_status == "all" && @filter_queue.blank? && @filter_class.blank? && @search_term.blank?
                       # For unfiltered, estimate or use cached count
                       [jobs_relation.limit(10_000).count, 10_000].min
                     else
                       jobs_relation.count
                     end
      @total_pages = [(@total_count.to_f / PER_PAGE).ceil, 1].max
      @recent_jobs = jobs_relation.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a

      # OPTIMIZE: Cache queue stats
      @queue_stats = calculate_queue_stats
      @available_queues = cached_available_queues
      @available_classes = cached_available_classes
      @paused_queues = cached_paused_queues
      @available_job_classes = cached_available_job_classes
    end

    def show
      @job = SolidQueue::Job.find(params[:id])
      @execution = SolidQueue::ClaimedExecution.where(job_id: @job.id).order(created_at: :desc).first
      @failed_execution = SolidQueue::FailedExecution.where(job_id: @job.id).order(created_at: :desc).first
    end

    def retry_failed
      failed_execution = SolidQueue::FailedExecution.find(params[:id])
      job = failed_execution.job

      # Re-enqueue the job
      job_class = job.class_name.constantize
      job_class.perform_later(*job.arguments)

      # NOTE: SolidQueue::FailedExecution doesn't have a retried_at column
      # The job is re-enqueued and will appear as a new job

      redirect_to admin_solid_queue_index_path, notice: "Job re-enqueued successfully"
    rescue StandardError => e
      redirect_to admin_solid_queue_index_path, alert: "Failed to retry job: #{e.message}"
    end

    def clear_finished
      count = SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)
      redirect_to admin_solid_queue_index_path, notice: "Cleared #{count} finished jobs"
    rescue StandardError => e
      redirect_to admin_solid_queue_index_path, alert: "Failed to clear jobs: #{e.message}"
    end

    def delete_job
      job = SolidQueue::Job.find(params[:id])
      job_id = job.id
      job.destroy
      redirect_to admin_solid_queue_index_path, notice: "Job ##{job_id} deleted successfully"
    rescue StandardError => e
      redirect_to admin_solid_queue_index_path, alert: "Failed to delete job: #{e.message}"
    end

    def delete_failed
      job = SolidQueue::Job.find(params[:id])
      job_id = job.id
      job.destroy
      redirect_to admin_solid_queue_index_path, notice: "Failed job ##{job_id} deleted successfully"
    rescue StandardError => e
      redirect_to admin_solid_queue_index_path, alert: "Failed to delete job: #{e.message}"
    end

    def unqueue_job
      job = SolidQueue::Job.find(params[:id])
      job_id = job.id

      # Cancel pending jobs by marking them as finished
      if job.finished_at.nil?
        job.update!(finished_at: Time.current)
        redirect_to admin_solid_queue_index_path, notice: "Job ##{job_id} unqueued (marked as finished)"
      else
        redirect_to admin_solid_queue_index_path, alert: "Job ##{job_id} is already finished"
      end
    rescue StandardError => e
      redirect_to admin_solid_queue_index_path, alert: "Failed to unqueue job: #{e.message}"
    end

    def pause_queue
      queue_name = params[:queue_name]
      SolidQueue::Pause.find_or_create_by!(queue_name: queue_name)
      redirect_to admin_solid_queue_index_path(queue: queue_name), notice: "Queue '#{queue_name}' paused"
    rescue StandardError => e
      redirect_to admin_solid_queue_index_path, alert: "Failed to pause queue: #{e.message}"
    end

    def unpause_queue
      queue_name = params[:queue_name]
      SolidQueue::Pause.where(queue_name: queue_name).destroy_all
      redirect_to admin_solid_queue_index_path(queue: queue_name), notice: "Queue '#{queue_name}' unpaused"
    rescue StandardError => e
      redirect_to admin_solid_queue_index_path, alert: "Failed to unpause queue: #{e.message}"
    end

    def create_job
      class_name = params[:class_name]
      queue_name = params[:queue_name].presence || "default"
      arguments = parse_arguments(params[:arguments])
      priority = (params[:priority] || 0).to_i
      scheduled_at = params[:scheduled_at].present? ? Time.parse(params[:scheduled_at]) : nil

      # Validate class exists
      job_class = class_name.constantize

      # Create the job
      if scheduled_at
        job_class.set(queue: queue_name, priority: priority).perform_at(scheduled_at, *arguments)
        message = "Job scheduled for #{scheduled_at.strftime('%Y-%m-%d %H:%M:%S')}"
      else
        job_class.set(queue: queue_name, priority: priority).perform_later(*arguments)
        message = "Job enqueued successfully"
      end

      redirect_to admin_solid_queue_index_path, notice: message
    rescue NameError
      redirect_to admin_solid_queue_index_path, alert: "Class '#{class_name}' not found"
    rescue StandardError => e
      redirect_to admin_solid_queue_index_path, alert: "Failed to create job: #{e.message}"
    end

    def bulk_delete
      job_ids_param = params[:job_ids]
      return redirect_to admin_solid_queue_index_path, alert: "No jobs selected" if job_ids_param.blank?

      # Handle both array and comma-separated string
      job_ids = job_ids_param.is_a?(Array) ? job_ids_param : job_ids_param.split(",").map(&:strip)
      return redirect_to admin_solid_queue_index_path, alert: "No jobs selected" if job_ids.empty?

      count = SolidQueue::Job.where(id: job_ids).delete_all
      redirect_to admin_solid_queue_index_path, notice: "Deleted #{count} job(s)"
    rescue StandardError => e
      redirect_to admin_solid_queue_index_path, alert: "Failed to delete jobs: #{e.message}"
    end

    def bulk_unqueue
      job_ids_param = params[:job_ids]
      return redirect_to admin_solid_queue_index_path, alert: "No jobs selected" if job_ids_param.blank?

      # Handle both array and comma-separated string
      job_ids = job_ids_param.is_a?(Array) ? job_ids_param : job_ids_param.split(",").map(&:strip)
      return redirect_to admin_solid_queue_index_path, alert: "No jobs selected" if job_ids.empty?

      count = SolidQueue::Job.where(id: job_ids, finished_at: nil)
                             .update_all(finished_at: Time.current)
      redirect_to admin_solid_queue_index_path, notice: "Unqueued #{count} job(s)"
    rescue StandardError => e
      redirect_to admin_solid_queue_index_path, alert: "Failed to unqueue jobs: #{e.message}"
    end

    private

    def calculate_job_status_counts(base_jobs)
      current_time = Time.current

      # Pending: not finished and scheduled (or no schedule)
      pending_count = base_jobs.where(finished_at: nil)
                               .where("scheduled_at IS NULL OR scheduled_at <= ?", current_time)
                               .count

      # Running: jobs with claimed executions (scoped to base_jobs)
      running_job_ids = SolidQueue::ClaimedExecution
                        .where(job_id: base_jobs.select(:id))
                        .pluck(:job_id)
      running_count = running_job_ids.count

      # Failed: jobs with failed executions (scoped to base_jobs)
      failed_job_ids = SolidQueue::FailedExecution
                       .where(job_id: base_jobs.select(:id))
                       .pluck(:job_id)
      failed_count = failed_job_ids.count

      # Finished: jobs finished in last 24 hours
      finished_count = base_jobs.where.not(finished_at: nil)
                                .where("finished_at > ?", 24.hours.ago)
                                .count

      {
        pending: pending_count,
        running: running_count,
        failed: failed_count,
        finished: finished_count,
      }
    end

    def parse_arguments(arguments_string)
      return [] if arguments_string.blank?

      # Try to parse as JSON first
      JSON.parse(arguments_string)
    rescue JSON::ParserError
      # If not JSON, try to parse as Ruby array
      eval(arguments_string) # rubocop:disable Security/Eval
    rescue StandardError
      # Fallback: treat as single string argument
      [arguments_string]
    end

    def filter_jobs
      jobs = SolidQueue::Job.all

      # Filter by status
      case @filter_status
      when "pending"
        jobs = jobs.where(finished_at: nil)
                   .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
      when "running"
        job_ids = SolidQueue::ClaimedExecution.pluck(:job_id)
        jobs = jobs.where(id: job_ids)
      when "failed"
        job_ids = SolidQueue::FailedExecution.pluck(:job_id)
        jobs = jobs.where(id: job_ids)
      when "finished"
        jobs = jobs.where.not(finished_at: nil)
                   .where("finished_at > ?", 24.hours.ago)
      when "all"
        # By default, exclude finished jobs without errors unless explicitly requested
        unless @show_finished_successful
          # Get job IDs that have failed executions (these should be shown even if finished)
          failed_job_ids = SolidQueue::FailedExecution.pluck(:job_id)

          # Show: unfinished jobs OR finished jobs that have failed executions
          # This excludes successful finished jobs (finished but no failed execution)
          jobs = if failed_job_ids.any?
                   jobs.where("finished_at IS NULL OR id IN (?)", failed_job_ids)
                 else
                   # No failed jobs exist, so only show unfinished jobs
                   jobs.where(finished_at: nil)
                 end
        end
        # If @show_finished_successful is true, show all jobs (no additional filtering)
      end

      # Filter by queue
      jobs = jobs.where(queue_name: @filter_queue) if @filter_queue.present?

      # Filter by class name
      jobs = jobs.where(class_name: @filter_class) if @filter_class.present?

      # Search
      if @search_term.present?
        jobs = jobs.where(
          "class_name ILIKE ? OR queue_name ILIKE ? OR id::text ILIKE ?",
          "%#{@search_term}%", "%#{@search_term}%", "%#{@search_term}%"
        )
      end

      jobs.order(created_at: :desc)
    end

    def calculate_queue_stats
      # OPTIMIZE: Get all queue names in one query
      queues = SolidQueue::Job.distinct.pluck(:queue_name)
      return {} if queues.empty?

      stats = {}
      current_time = Time.current

      # OPTIMIZE: Batch queries for all queues
      queues.each do |queue_name|
        jobs_scope = SolidQueue::Job.where(queue_name: queue_name)
        job_ids = jobs_scope.pluck(:id)

        # OPTIMIZE: Single query for pending count
        pending_count = jobs_scope.where(finished_at: nil)
                                  .where("scheduled_at IS NULL OR scheduled_at <= ?", current_time)
                                  .count

        # OPTIMIZE: Use exists? checks before counting
        running_count = job_ids.any? ? SolidQueue::ClaimedExecution.where(job_id: job_ids).count : 0
        failed_count = job_ids.any? ? SolidQueue::FailedExecution.where(job_id: job_ids).count : 0

        stats[queue_name] = {
          pending: pending_count,
          running: running_count,
          failed: failed_count,
          avg_duration: calculate_avg_duration(jobs_scope),
        }
      end

      stats
    end

    def calculate_avg_duration(jobs)
      # OPTIMIZE: Use SQL aggregation instead of Ruby calculation
      # Calculate average duration for recent finished jobs (last 24 hours)
      # Limit to 100 most recent jobs to avoid GROUP BY issues with aggregates
      durations = jobs.where.not(finished_at: nil)
                      .where.not(created_at: nil)
                      .where("finished_at > ?", 24.hours.ago)
                      .order(finished_at: :desc)
                      .limit(100)
                      .pluck(Arel.sql("EXTRACT(EPOCH FROM (finished_at - created_at))"))

      return 0 if durations.empty?

      (durations.sum.to_f / durations.size).round(2)
    end

    # Cache frequently accessed data
    def cached_available_queues
      Rails.cache.fetch("admin_solid_queue_queues", expires_in: 5.minutes) do
        SolidQueue::Job.distinct.pluck(:queue_name).compact.sort
      end
    end

    def cached_available_classes
      Rails.cache.fetch("admin_solid_queue_classes", expires_in: 5.minutes) do
        SolidQueue::Job.distinct.pluck(:class_name).compact.sort
      end
    end

    def cached_paused_queues
      Rails.cache.fetch("admin_solid_queue_paused", expires_in: 1.minute) do
        SolidQueue::Pause.pluck(:queue_name).to_set
      end
    end

    def cached_available_job_classes
      Rails.cache.fetch("admin_solid_queue_job_classes", expires_in: 1.hour) do
        # Find all ApplicationJob subclasses by scanning files
        job_classes = []

        # Search in app/jobs directory
        Dir[Rails.root.join("app/jobs/**/*_job.rb")].each do |file|
          # Extract class name from file path
          relative_path = file.gsub("#{Rails.root.join('app/jobs/')}", "").gsub(".rb", "")
          # Handle namespaces correctly: convert path to class name
          parts = relative_path.split("/")
          class_name = parts.map { |part| part.camelize }.join("::")

          # Try to constantize and verify it's an ApplicationJob subclass
          # This will trigger autoloading if needed
          klass = class_name.constantize
          job_classes << class_name if klass < ApplicationJob && klass != ApplicationJob
        rescue NameError, LoadError, ArgumentError, SyntaxError => e
          # Skip if class can't be loaded (might not be autoloaded yet or has syntax errors)
          Rails.logger.debug { "Could not load job class from #{file}: #{e.class} - #{e.message}" }
          next
        end

        # Sort by namespace and class name for better UX
        job_classes.uniq.sort
      end
    end
  end
end
