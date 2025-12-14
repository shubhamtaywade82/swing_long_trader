# Solid Queue Setup Guide

## ✅ Production-Ready Configuration

Solid Queue is configured to run alongside your Rails app via Procfile. This is the **official, production-safe** way to run Solid Queue.

## 📋 Quick Start

### Development

```bash
# Use Foreman to run web + worker + assets together
foreman start -f Procfile.dev
```

This starts:
- Web server (Rails)
- Solid Queue worker
- JavaScript build watcher
- CSS watcher

### Production

```bash
# Use Procfile (web + worker)
foreman start
```

Or deploy with a process manager (Heroku, Dokku, etc.) that reads `Procfile`.

## 🔧 Configuration Files

### Procfile (Production)

```procfile
web: bundle exec rails server -p ${PORT:-3000} -b 0.0.0.0
worker: bundle exec rails solid_queue:start
```

### Procfile.dev (Development)

```procfile
web: env RUBY_DEBUG_OPEN=true bin/rails server
worker: bundle exec rails solid_queue:start
js: yarn build --watch
css: yarn watch:css
```

### config/queue.yml

```yaml
production:
  workers:
    - queues: <%= ENV.fetch("QUEUES", "*") %>
      threads: <%= ENV.fetch("RAILS_MAX_THREADS", 5).to_i %>
      processes: <%= ENV.fetch("JOB_CONCURRENCY", 1).to_i %>
      polling_interval: 0.1
```

## 🎯 Queue Configuration

### Default Behavior

By default, the worker processes **all queues** with **5 threads** and **1 process**.

### Custom Queue Processing

To process specific queues only:

```bash
QUEUES=screener,ai_evaluation RAILS_MAX_THREADS=3 bundle exec rails solid_queue:start
```

### Queue-to-Job Mapping

| Queue | Jobs | Purpose |
|-------|------|---------|
| `screener` | SwingScreenerJob, LongtermScreenerJob, AutomatedScreenerJob | Stock screening |
| `ai_evaluation` | AIRankerJob | AI evaluation (cost-controlled) |
| `execution` | ExecutorJob, ProcessApprovedJob | Order execution |
| `notifier` | NotifierJob | Telegram notifications |
| `monitoring` | MonitorJob, ExitMonitorJob, SyncJob | Health checks |
| `background` | CalibrationJob, AnalysisJob, DailySnapshotJob | Background analysis |
| `data_ingestion` | DailyIngestorJob, WeeklyIngestorJob, IntradayFetcherJob | Data fetching |

## 🚀 Scaling Options

### Single Worker (Recommended for Start)

```bash
# Process all queues with 5 threads
bundle exec rails solid_queue:start
```

### Dedicated Queue Workers (Advanced)

```bash
# Screener worker (high priority)
worker_screener: QUEUES=screener RAILS_MAX_THREADS=3 bundle exec rails solid_queue:start

# AI worker (cost-controlled)
worker_ai: QUEUES=ai_evaluation RAILS_MAX_THREADS=2 bundle exec rails solid_queue:start

# Execution worker (critical)
worker_exec: QUEUES=execution RAILS_MAX_THREADS=3 bundle exec rails solid_queue:start
```

**Note:** Start with a single worker. Split only when you have:
- High job volume
- Different priority requirements
- Need for isolation

## 🔍 Monitoring & Debugging

### Check Configuration

```bash
rake solid_queue:check
```

Output:
- Queue adapter status
- Table existence
- Job counts (pending, running, failed)
- Queues in use
- Recent failures

### View Statistics

```bash
rake solid_queue:stats
```

Shows per-queue statistics:
- Pending/running/failed counts
- Average duration
- Max duration

### Clear Old Jobs

```bash
# Clear finished jobs older than 7 days (default)
rake solid_queue:clear_finished

# Clear finished jobs older than 30 days
rake solid_queue:clear_finished[30]
```

### Rails Console

```ruby
# Check queue adapter
Rails.application.config.active_job.queue_adapter
# => :solid_queue

# Enqueue a job
Screeners::SwingScreenerJob.perform_later

# Check job status
SolidQueue::Job.where(finished_at: nil).count
SolidQueue::FailedExecution.count

# View queues
SolidQueue::Job.distinct.pluck(:queue_name)
```

## 🛡️ Production Best Practices

### 1. Always Start Worker

**Critical:** The worker must be running for jobs to execute.

```bash
# Check if worker is running
ps aux | grep "solid_queue:start"

# Or check via MonitorJob
rake monitor:check
```

### 2. Monitor Failed Jobs

```bash
# Check failed jobs
rake solid_queue:check

# View in admin dashboard
# Visit /admin/solid_queue
```

### 3. Set Appropriate Concurrency

```bash
# Conservative (recommended for start)
RAILS_MAX_THREADS=5 bundle exec rails solid_queue:start

# Higher throughput (if needed)
RAILS_MAX_THREADS=10 bundle exec rails solid_queue:start
```

**Warning:** Higher concurrency = more DB connections. Ensure `database.yml` pool size matches.

### 4. Handle Failures

Failed jobs are:
- Logged to `solid_queue_failed_executions`
- Alerted via Telegram (if configured)
- Visible in admin dashboard

To retry:
```ruby
# In Rails console
failed_exec = SolidQueue::FailedExecution.find(id)
job_class = failed_exec.job.class_name.constantize
job_class.perform_later(*failed_exec.job.arguments)
```

## 🚨 Common Issues

### Jobs Not Running

**Symptom:** Jobs enqueue but never execute.

**Check:**
1. Worker is running: `ps aux | grep solid_queue`
2. Queue adapter: `Rails.application.config.active_job.queue_adapter`
3. Tables exist: `rake solid_queue:check`

**Fix:**
```bash
# Start worker
bundle exec rails solid_queue:start
```

### High Memory Usage

**Symptom:** Worker consumes too much memory.

**Fix:**
- Reduce `RAILS_MAX_THREADS` (default: 5)
- Reduce `JOB_CONCURRENCY` (default: 1)
- Clear old finished jobs: `rake solid_queue:clear_finished`

### Jobs Stuck

**Symptom:** Jobs remain in "running" state.

**Check:**
```ruby
# Find stuck jobs
SolidQueue::ClaimedExecution.where("created_at < ?", 1.hour.ago)
```

**Fix:**
- Restart worker
- Check for deadlocks: `rake solid_queue:check`

### Database Connection Errors

**Symptom:** "too many connections" errors.

**Fix:**
- Reduce `RAILS_MAX_THREADS`
- Increase `database.yml` pool size
- Ensure pool size >= threads * processes

## 📊 Admin Dashboard

Access Solid Queue admin at `/admin/solid_queue`:

- Jobs by status (pending, running, failed, finished)
- Jobs by queue
- Recent failures with error details
- Queue statistics
- Retry failed jobs
- Clear finished jobs

## ✅ Verification Checklist

- [ ] `Procfile` includes worker process
- [ ] `config/application.rb` sets `queue_adapter = :solid_queue`
- [ ] `config/queue.yml` configured
- [ ] All jobs specify `queue_as :queue_name`
- [ ] Worker starts successfully: `bundle exec rails solid_queue:start`
- [ ] Jobs enqueue: `Screeners::SwingScreenerJob.perform_later`
- [ ] Jobs execute: Check `solid_queue_jobs` table
- [ ] Failed jobs alert: Check Telegram
- [ ] Admin dashboard accessible: `/admin/solid_queue`

## 🎯 Next Steps

1. **Monitor job health**: Set up `MonitorJob` to run periodically
2. **Set up alerts**: Configure Telegram notifications for failures
3. **Tune concurrency**: Adjust `RAILS_MAX_THREADS` based on load
4. **Scale when needed**: Split workers by queue when volume increases

## 📚 References

- [Solid Queue GitHub](https://github.com/rails/solid_queue)
- [Rails Active Job](https://guides.rubyonrails.org/active_job_basics.html)
- [Foreman Documentation](https://github.com/ddollar/foreman)
