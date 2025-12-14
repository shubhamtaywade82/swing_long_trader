# Solid Queue perform_now Fix

## 🔴 Problem Identified

Even though Solid Queue was configured to run in a separate process, jobs were still executing in the web process because:

1. **"Run Now" button used sync mode** - When clicked, it set `sync=true`, which triggered synchronous execution directly in the controller
2. **Sync mode bypassed the queue** - Jobs ran inline using `Screeners::SwingScreener.call` instead of `perform_later`
3. **Web process blocked** - Synchronous execution consumed Ruby threads and blocked HTTP requests

## ✅ Solution Implemented

### 1. Removed Sync Mode Entirely

**Before (WRONG):**
```ruby
if sync
  # Runs synchronously in web process - BLOCKS!
  candidates = Screeners::SwingScreener.call(...)
else
  job = SwingScreenerJob.perform_later(...)
end
```

**After (CORRECT):**
```ruby
# Always use perform_later - jobs MUST run in worker process
queue_name = priority == "now" ? :screener_now : :screener
job = SwingScreenerJob.set(queue: queue_name).perform_later(...)
```

### 2. Implemented Queue Priorities

Instead of sync mode, we now use queue priorities:

- **"Run Screener"** → `:screener` queue (normal priority)
- **"Run Now"** → `:screener_now` queue (high priority, processed first)

Both still run in the worker process - "Run Now" just gets priority.

### 3. Updated Procfile

**Before:**
```procfile
worker: bundle exec rails solid_queue:start
```

**After:**
```procfile
worker: QUEUES=screener_now,screener,ai_evaluation,execution,monitoring,data_ingestion,background,notifier bundle exec rails solid_queue:start
```

Worker now listens to all queues, including the new `screener_now` priority queue.

### 4. Added PID Logging

Added process ID logging to verify jobs run in worker process:

```ruby
Rails.logger.info(
  "[SwingScreenerJob] Starting worker_pid=#{Process.pid} queue=#{queue_name}"
)
```

When jobs run correctly:
- Web process PID ≠ Worker process PID
- Logs appear in worker terminal, not web terminal

### 5. Updated Views

**Before:**
```erb
<%= f.hidden_field :sync, value: "false" %>
<button onclick="...set sync to 'true'...">Run Now</button>
```

**After:**
```erb
<%= f.hidden_field :priority, value: "normal" %>
<button onclick="...set priority to 'now'...">Run Now</button>
```

## 🔍 How to Verify It's Fixed

### 1. Check Queue Adapter

```bash
rails console
```

```ruby
Rails.application.config.active_job.queue_adapter
# => :solid_queue
```

### 2. Verify Separate Processes

```bash
# Start application
foreman start

# In another terminal, check processes
ps aux | grep -E '(rails|solid_queue)'
```

**Expected output:**
```
# Web process
rails server -p 3000

# Worker process  
rails solid_queue:start
```

**Two separate PIDs** = ✅ Correct

### 3. Check Job Execution PID

1. Click "Run Screener" button
2. Check logs in **worker terminal** (not web terminal)

**Expected log:**
```
[Screeners::SwingScreenerJob] Starting worker_pid=12345 queue=screener
```

**If PID matches web process** = ❌ Still broken (job running in web)

**If PID is different** = ✅ Fixed (job running in worker)

### 4. Test UI Responsiveness

1. Click "Run Screener"
2. Immediately try to navigate to another page
3. **Expected:** Page loads immediately (UI stays responsive)
4. **If broken:** Page hangs/freezes (job blocking web process)

### 5. Check Queue Status

```bash
rails console
```

```ruby
# Check jobs are queued (not running inline)
SolidQueue::Job.where(class_name: 'Screeners::SwingScreenerJob')
  .order(created_at: :desc)
  .limit(5)
  .pluck(:id, :queue_name, :finished_at)

# Should show jobs with queue_name = 'screener' or 'screener_now'
# finished_at should be nil for running jobs
```

## 📊 Queue Priority System

### Queue Names and Priorities

| Queue | Purpose | Priority | Concurrency |
|-------|---------|----------|-------------|
| `screener_now` | Immediate screener runs | High | 1 |
| `screener` | Normal screener runs | Normal | 1 |
| `ai_evaluation` | AI analysis jobs | Normal | 1-2 |
| `execution` | Trade execution | High | 1 |
| `monitoring` | Position monitoring | Normal | 1-2 |
| `data_ingestion` | Market data updates | Low | 2-3 |
| `background` | General background tasks | Low | 2-3 |
| `notifier` | Notifications (Telegram, etc.) | Low | 1-2 |

### How Priority Works

Solid Queue processes queues in the order they're listed in `QUEUES` environment variable. Jobs in `screener_now` are processed before `screener`.

**Example:**
```bash
QUEUES=screener_now,screener,ai_evaluation
```

This means:
1. All `screener_now` jobs process first
2. Then `screener` jobs
3. Then `ai_evaluation` jobs

## 🚨 Common Mistakes to Avoid

### ❌ NEVER Use perform_now

```ruby
# WRONG - runs in web process
SwingScreenerJob.perform_now(id)
```

```ruby
# CORRECT - runs in worker process
SwingScreenerJob.perform_later(id)
```

### ❌ NEVER Run Jobs Synchronously in Controllers

```ruby
# WRONG - blocks web process
def run_screener
  candidates = Screeners::SwingScreener.call(...)
end
```

```ruby
# CORRECT - enqueue to worker
def run_screener
  SwingScreenerJob.perform_later(...)
end
```

### ❌ NEVER Use :async or :inline Adapter

```ruby
# WRONG - runs in web process
config.active_job.queue_adapter = :async
config.active_job.queue_adapter = :inline
```

```ruby
# CORRECT - uses separate worker process
config.active_job.queue_adapter = :solid_queue
```

## ✅ Success Indicators

When correctly configured:

- ✅ Web UI stays responsive during job execution
- ✅ New HTTP requests work during screener runs
- ✅ Job logs appear in worker terminal, not web terminal
- ✅ Job PID ≠ Web PID
- ✅ Jobs visible in `solid_queue_jobs` table
- ✅ No request timeouts or UI freezes
- ✅ Screener results appear incrementally via broadcasts

## 📝 Files Changed

1. `app/controllers/dashboard_controller.rb`
   - Removed sync mode
   - Added queue priority support
   - Added PID logging

2. `app/jobs/screeners/swing_screener_job.rb`
   - Added PID logging

3. `app/jobs/screeners/longterm_screener_job.rb`
   - Added PID logging

4. `app/views/dashboard/swing_screener.html.erb`
   - Changed sync to priority
   - Removed sync-specific JavaScript handling

5. `app/views/dashboard/longterm_screener.html.erb`
   - Changed sync to priority
   - Removed sync-specific JavaScript handling

6. `Procfile`
   - Added all queues to worker command

7. `Procfile.dev`
   - Added all queues to worker command

## 🎯 Key Takeaways

1. **NEVER use `perform_now`** for production jobs
2. **ALWAYS use `perform_later`** - jobs must run in worker process
3. **Use queue priorities** instead of sync mode for "immediate" execution
4. **Verify process separation** using PID logging
5. **Worker must listen to all queues** used by the application

---

**Status:** ✅ Fixed - All jobs now run in separate worker process

**Last Updated:** After removing sync mode and implementing queue priorities
