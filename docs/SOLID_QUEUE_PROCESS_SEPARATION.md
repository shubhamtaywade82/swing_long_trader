# Solid Queue Process Separation Guide

## 🔴 CRITICAL: Why Process Separation is Required

**Solid Queue MUST run in a separate OS process from your Rails web server.**

### The Problem (What You Were Experiencing)

When Solid Queue runs in the same process as Puma:

- ✅ Jobs execute correctly
- ❌ Ruby threads are consumed by job execution
- ❌ Rails request threads are blocked
- ❌ Server cannot respond to new HTTP requests
- ❌ UI freezes while screener jobs run
- ❌ Database connections are shared and exhausted

### The Solution (What We Fixed)

**Two separate processes:**

1. **Process 1: Web Server (Puma)**
   - Handles HTTP requests
   - Serves the UI
   - Maintains WebSocket connections (ActionCable/Turbo)

2. **Process 2: Solid Queue Worker**
   - Executes background jobs
   - Polls database for jobs
   - Updates database records
   - Broadcasts updates via ActionCable

**Communication:** Database + ActionCable broadcasts (process-safe, no shared memory needed)

---

## ✅ Configuration Checklist

### 1. Procfile (REQUIRED)

Your `Procfile` must have both processes:

```procfile
web: bundle exec rails server -p ${PORT:-3000} -b 0.0.0.0
worker: bundle exec rails solid_queue:start
```

✅ **Current Status:** Correctly configured

### 2. Environment Configuration

#### Development (`config/environments/development.rb`)

```ruby
config.active_job.queue_adapter = :solid_queue
```

✅ **Status:** Now explicitly set

#### Production (`config/environments/production.rb`)

```ruby
config.active_job.queue_adapter = :solid_queue
config.solid_queue.connects_to = { database: { writing: :queue } }
```

✅ **Status:** Correctly configured

#### Test (`config/environments/test.rb`)

```ruby
config.active_job.queue_adapter = :test
```

✅ **Status:** Now explicitly set (test adapter runs jobs inline, which is safe for tests)

### 3. Puma Configuration (`config/puma.rb`)

**CRITICAL:** The Solid Queue plugin is DISABLED:

```ruby
# plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]  # DISABLED
```

✅ **Status:** Plugin disabled (commented out with explanation)

### 4. Deployment Configuration (`config/deploy.yml`)

**CRITICAL:** `SOLID_QUEUE_IN_PUMA` is REMOVED:

```yaml
env:
  clear:
    # DO NOT set SOLID_QUEUE_IN_PUMA=true - this causes blocking!
```

✅ **Status:** Removed (was causing the problem)

---

## 🚀 How to Start the Application

### Local Development (REQUIRED)

**DO NOT use `rails s` alone** - it will run jobs inline and block requests.

**Use Foreman (or Overmind):**

```bash
# Install foreman if needed
gem install foreman

# Start both processes
foreman start
```

This starts:
- `web` process (Rails server)
- `worker` process (Solid Queue)

**Alternative:** Use `Procfile.dev` for development:

```bash
foreman start -f Procfile.dev
```

### Production (Kamal)

Kamal will automatically use your `Procfile` and start both processes.

**Verify both processes are running:**

```bash
# SSH into server
kamal app exec "ps aux | grep -E '(rails|solid_queue)'"
```

You should see:
- One process: `rails server` (web)
- One process: `rails solid_queue:start` (worker)

---

## 🔍 Verification Steps

### 1. Check Queue Adapter

```bash
rails console
```

```ruby
Rails.application.config.active_job.queue_adapter
# => :solid_queue
```

❌ If it returns `:async` or `:inline` → jobs will block the server

### 2. Verify Separate Processes

```bash
ps aux | grep solid_queue
```

✅ **Should see:** Separate PID for `rails solid_queue:start`

❌ **If you don't see it:** Jobs are running inline

### 3. Check Environment Variable

```bash
env | grep SOLID_QUEUE_IN_PUMA
```

✅ **Should be:** Empty (not set)

❌ **If set to `true`:** Solid Queue will run in Puma (BLOCKING!)

### 4. Test Job Execution

1. Start both processes (`foreman start`)
2. Trigger a screener job
3. **Expected behavior:**
   - ✅ UI stays responsive
   - ✅ New HTTP requests work during job execution
   - ✅ Screener results appear incrementally
   - ✅ Server CPU doesn't spike to 100%

---

## 📊 Concurrency Configuration

### Solid Queue Worker Concurrency

Control how many jobs run simultaneously:

```bash
# Single queue, 3 concurrent jobs
RAILS_MAX_THREADS=3 bundle exec rails solid_queue:start

# Specific queues only
QUEUES=screener,ai_evaluation RAILS_MAX_THREADS=3 bundle exec rails solid_queue:start

# Single queue, 1 job at a time (recommended for screener)
QUEUES=screener RAILS_MAX_THREADS=1 bundle exec rails solid_queue:start
```

### Recommended Settings for Trading App

**Screener Queue:**
- Concurrency: 1 (prevents race conditions, ensures sequential processing)
- Command: `QUEUES=screener RAILS_MAX_THREADS=1 bundle exec rails solid_queue:start`

**AI Evaluation Queue:**
- Concurrency: 1-2 (prevents cost spikes, limits API rate limits)
- Command: `QUEUES=ai_evaluation RAILS_MAX_THREADS=2 bundle exec rails solid_queue:start`

**Execution Queue:**
- Concurrency: 1 (prevents double orders, ensures sequential execution)
- Command: `QUEUES=execution RAILS_MAX_THREADS=1 bundle exec rails solid_queue:start`

### Puma Thread Configuration

Your `config/puma.rb` is configured for request concurrency:

```ruby
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count
```

This allows Puma to handle multiple HTTP requests concurrently without blocking.

---

## 🔄 How UI Updates Work with Separate Processes

**Question:** "How will DB updates reflect live on the Rails screener UI table if jobs run in another process?"

**Answer:** Database + ActionCable/Turbo Broadcasts

### Flow (Correct & Safe):

```
Worker Process:
  ├─ Runs SwingScreenerJob
  ├─ Creates/updates ScreenerResult records
  ├─ Commits transaction
  └─ Broadcasts update via ActionCable

Web Process:
  ├─ Serves HTTP requests
  ├─ Maintains WebSocket connections
  └─ Receives broadcast → updates UI
```

**No shared memory required. No coupling between processes.**

This is exactly how GitHub, Shopify, Stripe handle background jobs.

### Broadcasting Correctly

**✅ CORRECT (After DB commit):**

```ruby
ActiveRecord::Base.transaction do
  screener_result.save!
end

# Broadcast AFTER commit
ActionCable.server.broadcast(
  "screener_run_#{screener_run_id}",
  payload
)
```

**❌ WRONG (Before commit or outside transaction):**

```ruby
# Broadcasting before commit can cause race conditions
ActionCable.server.broadcast(...)
screener_result.save!
```

---

## 🚨 Common Mistakes to Avoid

### ❌ Running Only `rails s`

```bash
rails s  # Jobs will run inline and block requests
```

**Fix:** Use `foreman start` to start both processes

### ❌ Using `:async` Adapter

```ruby
config.active_job.queue_adapter = :async  # Runs in same process!
```

**Fix:** Use `:solid_queue` and run worker in separate process

### ❌ Starting Solid Queue in Rails Initializers

```ruby
# config/initializers/solid_queue.rb
SolidQueue.start  # DON'T DO THIS
```

**Fix:** Use Procfile worker process

### ❌ Setting `SOLID_QUEUE_IN_PUMA=true`

```yaml
env:
  clear:
    SOLID_QUEUE_IN_PUMA: true  # DON'T DO THIS
```

**Fix:** Remove this env var, use separate process

### ❌ Broadcasting Before DB Commit

```ruby
ActionCable.server.broadcast(...)
record.save!  # Race condition!
```

**Fix:** Broadcast AFTER transaction commits

---

## ✅ Success Indicators

When correctly configured, you should observe:

- ✅ Web UI stays responsive during job execution
- ✅ New HTTP requests work during screener runs
- ✅ Screener results appear incrementally (via broadcasts)
- ✅ Server CPU doesn't spike to 100%
- ✅ `ps aux` shows two separate Rails processes
- ✅ Solid Queue jobs visible in `solid_queue_jobs` table
- ✅ No request timeouts or UI freezes

---

## 📚 Additional Resources

- [Solid Queue GitHub](https://github.com/rails/solid_queue)
- [Solid Queue Documentation](https://github.com/rails/solid_queue#readme)
- [ActionCable Broadcasting](https://guides.rubyonrails.org/action_cable_overview.html#broadcasting)
- [Procfile Format](https://devcenter.heroku.com/articles/procfile)

---

## 🆘 Troubleshooting

### Jobs Not Executing

1. Check worker process is running: `ps aux | grep solid_queue`
2. Check queue adapter: `Rails.application.config.active_job.queue_adapter`
3. Check jobs table: `rails console` → `SolidQueue::Job.count`

### UI Still Freezing

1. Verify `SOLID_QUEUE_IN_PUMA` is NOT set
2. Verify separate processes: `ps aux | grep -E '(rails|solid_queue)'`
3. Check Puma plugin is disabled in `config/puma.rb`
4. Verify queue adapter is `:solid_queue`, not `:async` or `:inline`

### Broadcasts Not Working

1. Check ActionCable is configured correctly
2. Verify broadcasts happen AFTER DB commit
3. Check WebSocket connections in browser DevTools
4. Verify Turbo Streams are set up correctly

---

**Last Updated:** After fixing process separation issue
**Status:** ✅ Configuration corrected and verified
