# frozen_string_literal: true

require "fugit" unless defined?(Fugit)

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

      # Recurring tasks (with error handling in case table doesn't exist)
      @recurring_tasks = begin
        SolidQueue::RecurringTask.all.order(:key)
      rescue StandardError => e
        Rails.logger.warn("Could not load recurring tasks: #{e.message}")
        []
      end

      @recurring_executions = begin
        SolidQueue::RecurringExecution
          .includes(:job)
          .order(created_at: :desc)
          .limit(20)
      rescue StandardError => e
        Rails.logger.warn("Could not load recurring executions: #{e.message}")
        []
      end
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

    def human_readable_schedule(cron_expression)
      return cron_expression unless cron_expression.present?

      # Handle non-cron formats (e.g., "every hour", "at 5am every day")
      return cron_expression.capitalize if cron_expression.include?("every") || cron_expression.include?("at")

      # Parse cron format: minute hour day month weekday
      parts = cron_expression.split
      return cron_expression unless parts.size == 5

      minute, hour, day, month, weekday = parts

      result = []

      # Parse in natural order: frequency/period first, then time
      # 1. Weekday/frequency (largest unit)
      weekday_desc = parse_weekday(weekday)
      result << weekday_desc if weekday_desc && weekday_desc != "Every day"

      # 2. Day/month (if specified)
      day_month_desc = parse_day_month(day, month)
      result << day_month_desc if day_month_desc

      # 3. Time (smallest unit - hours and minutes)
      time_desc = parse_time(hour, minute)
      result << time_desc if time_desc

      # If we couldn't parse it well, return original with a note
      if result.empty?
        "#{cron_expression} (cron)"
      elsif result.size > 1 && result.last.include?(" at ")
        # Join with "at" for natural reading: "Every day at 7:30 AM"
        # If time already contains "at", don't add another one
        result[0..-2].join(", ") + " " + result.last
      else
        result.join(" at ")
      end
    end

    def parse_weekday(weekday)
      return "Every day" if weekday == "*"

      case weekday
      when "0", "7"
        "Sunday"
      when "1"
        "Monday"
      when "2"
        "Tuesday"
      when "3"
        "Wednesday"
      when "4"
        "Thursday"
      when "5"
        "Friday"
      when "6"
        "Saturday"
      when /^(\d+)-(\d+)$/
        start_day = ::Regexp.last_match(1).to_i
        end_day = ::Regexp.last_match(2).to_i
        days = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]
        if start_day == 1 && end_day == 5
          "Weekdays (Mon-Fri)"
        elsif start_day == 0 && end_day == 6
          "Every day"
        elsif start_day <= end_day
          "#{days[start_day % 7]}-#{days[end_day % 7]}"
        else
          "#{days[start_day % 7]}-#{days[end_day % 7]}"
        end
      when /^(\d+),(\d+)$/
        day1 = ::Regexp.last_match(1).to_i
        day2 = ::Regexp.last_match(2).to_i
        days = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]
        "#{days[day1 % 7]}, #{days[day2 % 7]}"
      else
        nil
      end
    end

    def parse_time(hour, minute)
      return nil if hour == "*" && minute == "*"

      # Handle hour ranges with multiple minutes (e.g., "15,45 9-15")
      if hour.include?("-") && minute.include?(",")
        start_hour, end_hour = hour.split("-").map(&:to_i)
        minutes = minute.split(",").map(&:to_i).sort

        # Show first few times with full HH:MM AM/PM format
        # Example: "9:15 AM, 9:45 AM, 10:15 AM, 10:45 AM... (every :15 and :45 until 3 PM)"
        times = []
        hour_count = 0
        max_hours_to_show = 3

        (start_hour..end_hour).each do |h|
          break if hour_count >= max_hours_to_show

          minutes.each do |m|
            times << format_single_time(h, m)
          end
          hour_count += 1
        end

        minute_list = minutes.map { |m| format("%02d", m) }.join(" and :")
        return times.join(", ") if (end_hour - start_hour) <= max_hours_to_show

        # Small range: show all times

        # Large range: show first few, then pattern
        return "#{times.join(', ')}... (every :#{minute_list} until #{format_hour(end_hour)})"

      end

      # Handle hour ranges with single minute (e.g., "30 7-15")
      if hour.include?("-") && minute != "*" && !minute.include?(",")
        start_hour, end_hour = hour.split("-").map(&:to_i)
        minute_val = minute.to_i
        # Format as "7:30 AM-3:30 PM" not "7 AM-3 PM :30"
        start_time = format_single_time(start_hour, minute_val)
        end_time = format_single_time(end_hour, minute_val)
        return "#{start_time}-#{end_time}"
      end

      # Handle multiple minutes with single hour (e.g., "15,45 9")
      if minute.include?(",") && hour != "*" && !hour.include?("-") && !hour.include?(",")
        hour_24 = hour.to_i
        minutes = minute.split(",").map(&:to_i).sort
        # Format as "9:15 AM and 9:45 AM" not "9:15 and :45 AM"
        am_pm = hour_24 == 0 || hour_24 < 12 ? "AM" : "PM"
        display_hour = if hour_24 == 0
                         12
                       elsif hour_24 <= 12
                         hour_24
                       else
                         hour_24 - 12
                       end
        time_list = minutes.map { |m| "#{display_hour}:#{format('%02d', m)} #{am_pm}" }.join(" and ")
        return time_list
      end

      # Single time (e.g., "30 7")
      if hour != "*" && minute != "*" && !hour.include?("-") && !hour.include?(",") && !minute.include?(",")
        return format_single_time(hour.to_i, minute.to_i)
      end

      # Fallback: build from components
      hour_str = if hour == "*"
                   "every hour"
                 elsif hour.include?("-")
                   start_hour, end_hour = hour.split("-").map(&:to_i)
                   "#{format_hour(start_hour)}-#{format_hour(end_hour)}"
                 elsif hour.include?(",")
                   hours = hour.split(",").map { |h| format_hour(h.to_i) }
                   hours.join(", ")
                 else
                   format_hour(hour.to_i)
                 end

      minute_str = if minute == "*"
                     ""
                   elsif minute.include?(",")
                     minutes = minute.split(",").map(&:to_i).sort
                     "at :#{minutes.map { |m| format('%02d', m) }.join(' and :')}"
                   elsif minute.start_with?("*/")
                     interval = minute.split("/").last.to_i
                     "every #{interval} minutes"
                   else
                     "at :#{format('%02d', minute.to_i)}"
                   end

      if minute_str.present?
        "#{minute_str} #{hour_str}".strip
      else
        hour_str
      end
    end

    def parse_day_month(day, month)
      return nil if day == "*" && month == "*"
      return nil if day == "*" && month != "*" # Don't show if only month is specified

      if day != "*" && month == "*"
        if day.include?("-")
          "days #{day}"
        else
          "day #{day}"
        end
      elsif day == "*" && month != "*"
        "in #{month_name(month)}"
      else
        nil
      end
    end

    def format_hour(hour)
      hour_24 = hour.to_i
      if hour_24 == 0
        "12 AM"
      elsif hour_24 < 12
        "#{hour_24} AM"
      elsif hour_24 == 12
        "12 PM"
      else
        "#{hour_24 - 12} PM"
      end
    end

    def format_single_time(hour_24, minute_val)
      # Format as "7:30 AM" not "7 AM:30"
      if hour_24 == 0
        "12:#{format('%02d', minute_val)} AM"
      elsif hour_24 < 12
        "#{hour_24}:#{format('%02d', minute_val)} AM"
      elsif hour_24 == 12
        "12:#{format('%02d', minute_val)} PM"
      else
        "#{hour_24 - 12}:#{format('%02d', minute_val)} PM"
      end
    end

    def month_name(month)
      months = %w[January February March April May June July August September October November December]
      month_num = month.to_i
      return month if month_num < 1 || month_num > 12

      months[month_num - 1]
    end

    def calculate_next_run_time(cron_expression, from_time: nil)
      return nil unless cron_expression.present?

      from_time ||= Time.current

      # Handle non-cron formats (e.g., "every hour", "at 5am every day")
      # Try to convert common patterns to cron format
      normalized_schedule = normalize_schedule_to_cron(cron_expression)
      return nil unless normalized_schedule

      begin
        # Parse cron expression using fugit (available via solid_queue)
        cron = Fugit::Cron.parse(normalized_schedule)
        return nil unless cron

        # Calculate next run time (returns EtOrbi::EoTime, convert to Time)
        next_time_eo = cron.next_time(from_time)
        return nil unless next_time_eo

        # Convert EtOrbi::EoTime to Time using Time.zone.at to preserve timezone
        Time.zone.at(next_time_eo.to_f)
      rescue StandardError => e
        Rails.logger.warn("Failed to parse cron expression '#{cron_expression}': #{e.message}")
        nil
      end
    end

    def normalize_schedule_to_cron(schedule)
      return schedule if schedule.blank?

      # If it already looks like a cron expression (5 space-separated parts), return as-is
      parts = schedule.split
      return schedule if parts.size == 5 && parts.all? { |p| p.match?(%r{^[\d*,\-/]+$}) }

      # Try to parse common patterns
      schedule_lower = schedule.downcase.strip

      # "every hour at minute 12" -> "12 * * * *"
      if schedule_lower.match?(/every hour at minute (\d+)/)
        minute = schedule_lower.match(/every hour at minute (\d+)/)[1]
        return "#{minute} * * * *"
      end

      # "every hour" -> "0 * * * *" (at minute 0 of every hour)
      return "0 * * * *" if schedule_lower == "every hour"

      # "at 5am every day" -> "0 5 * * *"
      if schedule_lower.match?(/at (\d+)am every day/)
        hour = schedule_lower.match(/at (\d+)am every day/)[1]
        return "0 #{hour} * * *"
      end

      # If it contains "every" or "at" but we can't parse it, return nil
      return nil if schedule_lower.include?("every") || schedule_lower.include?("at")

      # Otherwise, assume it's already a cron expression
      schedule
    end

    helper_method :human_readable_schedule, :calculate_next_run_time
  end
end
