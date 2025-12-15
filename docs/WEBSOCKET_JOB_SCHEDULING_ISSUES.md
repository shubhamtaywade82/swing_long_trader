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

## Recommended Fix

Combine multiple solutions:

1. **Frontend**: Check if indicator exists before calling API
2. **Controller**: Check if job already queued/running
3. **Job**: Use database lock + Redis for thread tracking
4. **Thread**: Proper cleanup on stop
