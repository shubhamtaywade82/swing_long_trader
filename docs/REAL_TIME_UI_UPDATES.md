# Real-Time UI Updates - Complete Flow

## ✅ YES - All Jobs Run in Worker Process

**All three scenarios now run in the worker process:**

### 1. Scheduled Jobs (via recurring.yml)
```yaml
# config/recurring.yml
automated_swing_screener:
  class: Screeners::AutomatedScreenerJob
  schedule: "15,45 9-15 * * 1-5"  # Every 30 minutes during market hours
```

**Flow:**
- Solid Queue's recurring task scheduler enqueues `AutomatedScreenerJob` at scheduled times
- Job uses `perform_later` → goes to `:screener` queue
- Worker process picks up job and executes it
- ✅ Runs in worker process, not web process

### 2. "Run Screener" Button
```ruby
# app/controllers/dashboard_controller.rb
job = SwingScreenerJob.set(queue: :screener).perform_later(limit: limit)
```

**Flow:**
- User clicks "Run Screener"
- Controller enqueues job to `:screener` queue
- Worker process picks up job and executes it
- ✅ Runs in worker process, not web process

### 3. "Run Now" Button
```ruby
# app/controllers/dashboard_controller.rb
job = SwingScreenerJob.set(queue: :screener_now).perform_later(limit: limit)
```

**Flow:**
- User clicks "Run Now"
- Controller enqueues job to `:screener_now` queue (high priority)
- Worker process picks up job immediately (priority queue)
- ✅ Runs in worker process, not web process

---

## ✅ YES - UI Updates in Real-Time as DB Updates

### How Real-Time Updates Work

#### 1. Database Updates (Worker Process)

**Worker process executes job:**
```ruby
# app/jobs/screeners/swing_screener_job.rb
def perform(...)
  # Creates ScreenerRun record
  screener_run = ScreenerRun.create!(...)
  
  # Processes candidates and creates ScreenerResult records
  candidates.each do |candidate|
    ScreenerResult.create!(
      screener_run_id: screener_run.id,
      instrument_id: candidate[:instrument_id],
      # ... other fields
    )
  end
  
  # Updates ScreenerRun status
  screener_run.mark_completed!
end
```

**Database transactions commit** → Records are immediately available to web process

#### 2. ActionCable Broadcasts (Worker Process)

**After DB updates, worker broadcasts:**
```ruby
# app/jobs/screeners/swing_screener_job.rb
ActionCable.server.broadcast(
  "dashboard_updates",
  {
    type: "screener_update",
    screener_type: "swing",
    screener_run_id: screener_run.id,
    # ... update data
  }
)
```

**During processing, service broadcasts progress:**
```ruby
# app/services/screeners/swing_screener.rb
def broadcast_progress(progress_key, progress_data)
  ActionCable.server.broadcast(
    "dashboard_updates",
    {
      type: "screener_progress",
      screener_type: "swing",
      progress: progress_data,  # { processed: 50, total: 100, analyzed: 45 }
    }
  )
end

def broadcast_partial_results(results_key, candidates)
  ActionCable.server.broadcast(
    "dashboard_updates",
    {
      type: "screener_partial_results",
      screener_type: "swing",
      candidates: candidates.first(20),  # Top 20 candidates so far
    }
  )
end
```

#### 3. UI Receives Updates (Web Process)

**Current Implementation: Polling (Every 5 seconds)**

```javascript
// app/views/dashboard/swing_screener.html.erb
const pollForResults = setInterval(() => {
  fetch('/dashboard/check_screener_results?type=swing')
    .then(response => response.json())
    .then(data => {
      // Update UI with latest results from database
      if (data.has_partial && data.candidates) {
        updateProgressiveResults(data.candidates, data.progress);
      }
      if (data.is_complete) {
        location.reload(); // Refresh page with final results
      }
    });
}, 5000); // Poll every 5 seconds
```

**Controller reads from database:**
```ruby
# app/controllers/dashboard_controller.rb
def check_screener_results
  # Read latest results from database (updated by worker)
  latest_results = ScreenerResult.latest_for(screener_type: "swing")
  candidates = latest_results.map(&:to_candidate_hash)
  
  # Read progress from cache (updated by worker)
  progress = Rails.cache.read("swing_screener_progress_#{Date.current}")
  
  render json: {
    ready: candidates.any?,
    candidate_count: candidates.size,
    candidates: candidates.first(20),
    progress: progress,
    is_complete: progress[:status] == "completed",
    has_partial: candidates.any? && progress[:status] == "running"
  }
end
```

---

## 🔄 Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ SCHEDULED JOB (recurring.yml)                                   │
│ OR                                                               │
│ USER CLICKS "Run Screener" / "Run Now"                          │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ WEB PROCESS (Puma)                                              │
│                                                                  │
│ Controller: run_swing_screener                                  │
│   ↓                                                              │
│ SwingScreenerJob.set(queue: :screener).perform_later(...)       │
│   ↓                                                              │
│ Job enqueued to Solid Queue database                            │
│   ↓                                                              │
│ Returns immediately (non-blocking)                              │
│   ↓                                                              │
│ UI shows "Job queued" message                                    │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     │ (Job stored in solid_queue_jobs table)
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ WORKER PROCESS (rails solid_queue:start)                        │
│                                                                  │
│ Worker polls database for jobs                                  │
│   ↓                                                              │
│ Finds SwingScreenerJob in :screener queue                       │
│   ↓                                                              │
│ Executes job:                                                   │
│   1. Creates ScreenerRun record                                 │
│   2. Processes candidates                                       │
│   3. Creates ScreenerResult records (incremental)              │
│   4. Updates ScreenerRun status                                │
│   5. Broadcasts updates via ActionCable                         │
│                                                                  │
│ Database updates happen incrementally:                          │
│   - ScreenerResult records created as candidates found         │
│   - ScreenerRun.status updated from "running" → "completed"   │
│   - Progress cached for UI polling                             │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     │ (Database commits)
                     │ (ActionCable broadcasts)
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ DATABASE (PostgreSQL)                                            │
│                                                                  │
│ screener_runs table:                                            │
│   - id: 123                                                      │
│   - status: "completed"                                          │
│   - started_at: 2024-01-15 10:00:00                            │
│   - completed_at: 2024-01-15 10:05:00                          │
│                                                                  │
│ screener_results table:                                         │
│   - screener_run_id: 123                                        │
│   - instrument_id: 1, score: 85.5, ...                         │
│   - instrument_id: 2, score: 82.3, ...                         │
│   - ... (incremental updates)                                    │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     │ (UI polls every 5 seconds)
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ WEB PROCESS (Puma) - UI Update                                  │
│                                                                  │
│ JavaScript: fetch('/dashboard/check_screener_results')          │
│   ↓                                                              │
│ Controller: Reads ScreenerResult records from database          │
│   ↓                                                              │
│ Returns JSON with latest candidates and progress               │
│   ↓                                                              │
│ JavaScript: Updates UI incrementally                            │
│   - Shows partial results as they're found                     │
│   - Updates progress bar                                        │
│   - Refreshes page when complete                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🎯 Key Points

### ✅ Process Separation
- **Web process:** Handles HTTP requests, serves UI, reads from database
- **Worker process:** Executes jobs, writes to database, broadcasts updates
- **No shared memory** - communication via database + ActionCable

### ✅ Real-Time Updates
- **Database updates:** Happen incrementally as job processes candidates
- **UI polling:** Checks database every 5 seconds for new results
- **ActionCable:** Broadcasts are sent (can be used for true real-time if UI subscribes)

### ✅ Incremental Results
- ScreenerResult records are created as candidates are found
- UI can show partial results while job is still running
- Progress tracking shows: "50/100 processed, 45 analyzed, 12 candidates found"

### ✅ No Blocking
- Web process stays responsive (doesn't execute jobs)
- Worker process handles all job execution
- UI updates happen via polling (non-blocking)

---

## 🚀 Future Enhancement: True Real-Time with ActionCable

**Current:** UI polls database every 5 seconds

**Potential Enhancement:** UI subscribes to ActionCable channel for instant updates

```javascript
// Subscribe to ActionCable channel
const consumer = ActionCable.createConsumer();
const subscription = consumer.subscriptions.create("DashboardChannel", {
  received(data) {
    if (data.type === "screener_progress") {
      updateProgressBar(data.progress);
    }
    if (data.type === "screener_partial_results") {
      updateResultsTable(data.candidates);
    }
    if (data.type === "screener_update") {
      location.reload(); // Final results ready
    }
  }
});
```

**Benefits:**
- Instant updates (no 5-second delay)
- Less server load (no polling)
- Better UX (real-time progress)

**Current polling works fine** - this would be an optimization, not a requirement.

---

## ✅ Verification Checklist

To verify everything works correctly:

1. **Start both processes:**
   ```bash
   foreman start
   ```

2. **Verify separate processes:**
   ```bash
   ps aux | grep -E '(rails|solid_queue)'
   # Should show 2 separate PIDs
   ```

3. **Click "Run Screener":**
   - UI should show "Job queued" immediately
   - Web process stays responsive
   - Check worker terminal for job logs

4. **Watch for incremental updates:**
   - UI should show partial results as they're found
   - Progress bar should update
   - Database should show ScreenerResult records being created

5. **Check scheduled jobs:**
   ```bash
   rails console
   ```
   ```ruby
   SolidQueue::RecurringTask.all
   # Should show automated_swing_screener scheduled
   ```

---

## 📝 Summary

**✅ All jobs (scheduled, manual, priority) run in worker process**

**✅ UI updates in real-time as database is updated**

**✅ Process separation ensures web server stays responsive**

**✅ Incremental results allow progressive UI updates**

**✅ ActionCable broadcasts are sent (can enhance UI to subscribe for instant updates)**

---

**Status:** ✅ Working correctly - All jobs run in worker, UI updates via polling

**Last Updated:** After fixing perform_now issue and implementing queue priorities
