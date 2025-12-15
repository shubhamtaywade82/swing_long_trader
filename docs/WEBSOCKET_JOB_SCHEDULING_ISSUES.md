# WebSocket Job Scheduling Issues & Solutions

## Current Issues

### ❌ Issue 1: No Job Uniqueness/Locking

**Problem:**
- Multiple jobs can be enqueued for the same screener/instruments
- Each job creates a thread, even if one is already running
- Thread check (`@@active_threads`) only works within same process
- Multiple worker processes = multiple duplicate streams

**Current Flow:**
```
User refreshes page → startLtpUpdates() → POST /screeners/ltp/start
→ Controller enqueues job → Job checks @@active_threads
→ If not found, creates thread
```

**Problem Scenarios:**
1. User refreshes page multiple times → Multiple jobs enqueued
2. Multiple worker processes → Each has own @@active_threads map
3. Job retries → Could create duplicate threads

### ❌ Issue 2: Race Condition

**Problem:**
```ruby
# Check if running
if @@active_threads.key?(stream_key) && @@active_threads[stream_key].alive?
  return
end

# Gap here - another job could start between check and thread creation

# Create thread
websocket_thread = Thread.new do
  @@active_threads[stream_key] = websocket_thread
end
```

**Issue:** Two jobs could both pass the check and create duplicate threads.

### ❌ Issue 3: No Job-Level Deduplication

**Problem:**
- SolidQueue doesn't prevent duplicate jobs
- Each `perform_later` call creates a new job entry
- No mechanism to check if job is already queued/running

### ❌ Issue 4: Page Refresh Creates New Jobs

**Problem:**
- Every page load calls `startLtpUpdates()`
- Each call enqueues a new job
- Even if thread exists, job is still created in queue

## Solutions

### ✅ Solution 1: Add Job-Level Uniqueness Check

Check if job is already queued/running before enqueueing:

```ruby
# In controller
def start_ltp_updates
  # Check if job already exists in queue
  existing_job = find_existing_websocket_job(...)
  if existing_job
    return render json: { status: "already_running", job_id: existing_job.id }
  end
  
  # Only enqueue if not exists
  job = MarketHub::WebsocketTickStreamerJob.perform_later(...)
end
```

### ✅ Solution 2: Use Database Lock for Thread Creation

Use database-level locking to prevent race conditions:

```ruby
# In job
def perform(...)
  stream_key = stream_key(...)
  
  # Use database lock to prevent duplicates
  lock_key = "websocket_stream_#{stream_key}"
  
  ActiveRecord::Base.connection.execute(
    "SELECT pg_advisory_lock(hashtext('#{lock_key}'))"
  )
  
  begin
    # Check and create thread atomically
    if @@active_threads.key?(stream_key) && @@active_threads[stream_key].alive?
      return
    end
    
    # Create thread...
  ensure
    ActiveRecord::Base.connection.execute(
      "SELECT pg_advisory_unlock(hashtext('#{lock_key}'))"
    )
  end
end
```

### ✅ Solution 3: Frontend Check Before Enqueueing

Check if stream is already active before calling API:

```javascript
// Check if indicator already exists (stream running)
if (document.querySelector('.ltp-status-indicator.active')) {
  console.log('LTP updates already active');
  return;
}

// Only call API if not already running
fetch('/screeners/ltp/start', ...)
```

### ✅ Solution 4: Use Redis for Cross-Process Thread Tracking

Replace `@@active_threads` with Redis for multi-process support:

```ruby
# Use Redis instead of class variable
def thread_running?(stream_key)
  Redis.current.exists("websocket_stream:#{stream_key}")
end

def mark_thread_running(stream_key)
  Redis.current.setex("websocket_stream:#{stream_key}", 3600, "1")
end

def mark_thread_stopped(stream_key)
  Redis.current.del("websocket_stream:#{stream_key}")
end
```

## ✅ Implemented Solutions

### 1. Frontend Deduplication ✅
- Checks if indicator exists before calling API
- Prevents duplicate requests on page refresh

### 2. Controller-Level Checks ✅
- Checks if stream is running (cross-process via cache)
- Checks if job is already queued/running in SolidQueue
- Returns appropriate status (`already_running`, `queued`)

### 3. Cross-Process Thread Tracking ✅
- Uses Rails.cache (SolidCache) for cross-process tracking
- Stores stream status with heartbeat mechanism
- TTL-based expiration for stale streams

### 4. Health Check Job ✅
- Periodic cleanup of stale streams
- Monitoring and logging
- Runs every 5 minutes during market hours

### 5. Improved Thread Management ✅
- Better cleanup on stop
- Graceful shutdown support
- Thread status monitoring

## Implementation Details

### Cross-Process Tracking

```ruby
# Stream status stored in cache
cache_key = "websocket_stream:#{stream_key}"
Rails.cache.write(cache_key, {
  status: "running",
  process_id: Process.pid,
  started_at: Time.current.iso8601,
  heartbeat: Time.current.iso8601,  # Refreshed every 30 seconds
}, expires_in: 1.hour)
```

### Health Check

```ruby
# Runs every 5 minutes during market hours
MarketHub::WebsocketHealthCheckJob
- Cleans up stale threads
- Monitors active streams
- Logs health status
```

### Stream Status Check

```ruby
# Checks both in-process threads and cache
def stream_running?(stream_key, cache_key)
  # 1. Check in-process thread (fast)
  return true if @@active_threads[key]&.alive?
  
  # 2. Check cache (cross-process)
  cache_data = Rails.cache.read(cache_key)
  return false unless cache_data&.dig(:status) == "running"
  
  # 3. Check heartbeat is recent (< 2 minutes)
  heartbeat_time = Time.parse(cache_data[:heartbeat])
  Time.current - heartbeat_time < 2.minutes
end
```
