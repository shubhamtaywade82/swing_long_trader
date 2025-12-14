# frozen_string_literal: true

namespace :solid_queue do
  desc "Check Solid Queue configuration and status"
  task check: :environment do
    puts "🔍 Solid Queue Configuration Check"
    puts "=" * 60

    # Check queue adapter
    adapter = Rails.application.config.active_job.queue_adapter
    puts "Queue Adapter: #{adapter}"
    unless adapter == :solid_queue
      puts "⚠️  WARNING: Queue adapter is not :solid_queue"
    end

    # Check tables exist
    if ActiveRecord::Base.connection.table_exists?("solid_queue_jobs")
      puts "✅ solid_queue_jobs table exists"
    else
      puts "❌ solid_queue_jobs table missing - run migrations"
    end

    # Check job counts
    pending = SolidQueue::Job.where(finished_at: nil)
                             .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
                             .count
    running = SolidQueue::ClaimedExecution.count
    failed = SolidQueue::FailedExecution.count

    puts "\n📊 Job Status:"
    puts "  Pending: #{pending}"
    puts "  Running: #{running}"
    puts "  Failed: #{failed}"

    # Check queues
    queues = SolidQueue::Job.distinct.pluck(:queue_name).compact
    if queues.any?
      puts "\n📋 Queues in use:"
      queues.each do |queue|
        count = SolidQueue::Job.where(queue_name: queue, finished_at: nil).count
        puts "  #{queue}: #{count} pending"
      end
    else
      puts "\n📋 No jobs in queue"
    end

    # Check recent failures
    if failed.positive?
      puts "\n❌ Recent Failures:"
      SolidQueue::FailedExecution
        .includes(:job)
        .order(created_at: :desc)
        .limit(5)
        .each do |failed_exec|
        puts "  #{failed_exec.job.class_name}: #{failed_exec.error_class}"
        puts "    #{failed_exec.error_message&.truncate(80)}"
      end
    end

    puts "\n" + "=" * 60
  end

  desc "Show queue statistics"
  task stats: :environment do
    puts "📊 Solid Queue Statistics"
    puts "=" * 60

    queues = SolidQueue::Job.distinct.pluck(:queue_name).compact

    queues.each do |queue_name|
      jobs = SolidQueue::Job.where(queue_name: queue_name)
      pending = jobs.where(finished_at: nil)
                   .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
                   .count
      running = jobs.joins(:claimed_executions).count
      failed = jobs.joins(:failed_executions).count

      completed = jobs.where.not(finished_at: nil)
                     .where("finished_at > ?", 24.hours.ago)
                     .limit(100)

      durations = completed.filter_map do |job|
        next unless job.created_at && job.finished_at

        (job.finished_at - job.created_at).to_f
      end

      avg_duration = durations.any? ? (durations.sum / durations.size).round(2) : 0
      max_duration = durations.any? ? durations.max.round(2) : 0

      puts "\n#{queue_name.upcase}:"
      puts "  Pending: #{pending}"
      puts "  Running: #{running}"
      puts "  Failed: #{failed}"
      puts "  Avg Duration: #{avg_duration}s"
      puts "  Max Duration: #{max_duration}s"
    end

    puts "\n" + "=" * 60
  end

  desc "Clear finished jobs older than specified days (default: 7)"
  task :clear_finished, [:days] => :environment do |_t, args|
    days = (args[:days] || 7).to_i
    cutoff = days.days.ago

    count = SolidQueue::Job.where.not(finished_at: nil)
                           .where("finished_at < ?", cutoff)
                           .count

    if count.positive?
      SolidQueue::Job.where.not(finished_at: nil)
                     .where("finished_at < ?", cutoff)
                     .delete_all

      puts "✅ Cleared #{count} finished jobs older than #{days} days"
    else
      puts "ℹ️  No finished jobs older than #{days} days to clear"
    end
  end
end
