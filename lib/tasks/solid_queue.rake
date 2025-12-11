# frozen_string_literal: true

namespace :solid_queue do
  desc 'Verify SolidQueue tables exist'
  task verify: :environment do
    required_tables = %w[
      solid_queue_jobs
      solid_queue_claimed_executions
      solid_queue_failed_executions
      solid_queue_recurring_executions
      solid_queue_scheduled_executions
      solid_queue_blocked_executions
    ]

    puts "🔍 Verifying SolidQueue tables..."
    puts "=" * 60

    all_exist = true
    required_tables.each do |table_name|
      exists = ActiveRecord::Base.connection.table_exists?(table_name)
      status = exists ? "✅" : "❌"
      puts "#{status} #{table_name}"

      unless exists
        all_exist = false
      end
    end

    puts ""
    if all_exist
      puts "✅ All SolidQueue tables exist!"
      puts ""
      puts "To install SolidQueue tables, run:"
      puts "  rails solid_queue:install"
      puts "  rails db:migrate"
    else
      puts "❌ Some SolidQueue tables are missing!"
      puts ""
      puts "To install SolidQueue, run:"
      puts "  rails solid_queue:install"
      puts "  rails db:migrate"
      exit 1
    end
  end

  desc 'Show SolidQueue status'
  task status: :environment do
    unless ActiveRecord::Base.connection.table_exists?('solid_queue_jobs')
      puts "❌ SolidQueue is not installed"
      puts "   Run: rails solid_queue:install && rails db:migrate"
      exit 1
    end

    pending = SolidQueue::Job.where(finished_at: nil).count
    running = SolidQueue::ClaimedExecution.count
    failed = SolidQueue::FailedExecution.count
    scheduled = SolidQueue::ScheduledExecution.count

    puts "📊 SolidQueue Status"
    puts "=" * 60
    puts "Pending jobs:   #{pending}"
    puts "Running jobs:   #{running}"
    puts "Failed jobs:    #{failed}"
    puts "Scheduled jobs: #{scheduled}"
    puts ""

    if failed > 0
      puts "⚠️  There are #{failed} failed jobs"
      puts "   Run: rails solid_queue:failed to view details"
    end
  end

  desc 'List failed jobs'
  task failed: :environment do
    unless ActiveRecord::Base.connection.table_exists?('solid_queue_failed_executions')
      puts "❌ SolidQueue is not installed"
      exit 1
    end

    failed_jobs = SolidQueue::FailedExecution.order(created_at: :desc).limit(10)

    if failed_jobs.empty?
      puts "✅ No failed jobs"
      return
    end

    puts "❌ Failed Jobs (last 10)"
    puts "=" * 60

    failed_jobs.each do |failed|
      puts "Job ID: #{failed.job_id}"
      puts "Error: #{failed.error_class}"
      puts "Message: #{failed.error_message&.split("\n")&.first}"
      puts "Failed at: #{failed.created_at}"
      puts "-" * 60
    end
  end
end

