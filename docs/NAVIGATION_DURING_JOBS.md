# Navigation During Job Execution

## ✅ What Happens When You Navigate Away

### Scenario: You Click "Run Screener" Then Navigate to Another Page

**Example Flow:**
1. You're on `/dashboard/swing_screener`
2. You click "Run Screener" → Job enqueued
3. You navigate to `/dashboard/positions` (or any other page)
4. Job continues running in worker process
5. You navigate back to `/dashboard/swing_screener`
6. You see the latest results

---

## 🔄 Complete Flow with Navigation

### 1. Job Starts (On Screener Page)

```
User clicks "Run Screener"
    ↓
Web Process: Enqueues job (non-blocking)
    ↓
UI: Shows "Job queued" message
    ↓
JavaScript: Starts polling every 5 seconds
    ↓
ActionCable: Global subscription active (persists across pages)
```

### 2. User Navigates Away (e.g., to Positions Page)

```
User clicks "Positions" in sidebar
    ↓
Page navigation occurs (Turbo/standard navigation)
    ↓
Screener page JavaScript: Polling stops (setInterval cleared)
    ↓
ActionCable subscription: STILL ACTIVE (global, persists)
    ↓
Worker process: CONTINUES executing job
    ↓
Database: CONTINUES being updated incrementally
    ↓
ActionCable broadcasts: CONTINUE being sent
```

**Key Points:**
- ✅ **Polling stops** - Page-specific polling JavaScript stops (that's fine)
- ✅ **ActionCable subscription continues** - Global subscription in dashboard layout persists
- ✅ **Job continues running** - Worker process unaffected by navigation
- ✅ **Database updates continue** - ScreenerResult records keep being created
- ✅ **Broadcasts continue** - ActionCable broadcasts are sent (but UI might not be on screener page)

### 3. While on Another Page

**If you're on `/dashboard/positions`:**
- ActionCable subscription receives broadcasts
- JavaScript checks if you're on screener page before updating UI
- If not on screener page, broadcasts are logged but UI doesn't update
- Job continues running in background

**Code:**
```javascript
// app/javascript/controllers/dashboard_controller.js
handleScreenerUpdate(data) {
  // Only reload if on screener page
  setTimeout(() => {
    if (window.location.pathname.includes("screener")) {
      window.location.reload();
    }
  }, 2000);
}
```

### 4. User Returns to Screener Page

```
User clicks "Swing Screener" in sidebar
    ↓
Controller action: swing_screener
    ↓
Reads from database: ScreenerResult.latest_for(...)
    ↓
Shows latest results (completed or partial)
    ↓
If job still running: New polling starts
    ↓
If job completed: Shows final results immediately
```

**Code:**
```ruby
# app/controllers/dashboard_controller.rb
def swing_screener
  # Read latest results from database (updated by worker)
  latest_results = ScreenerResult.latest_for(screener_type: "swing", limit: @limit)
  @candidates = latest_results.map(&:to_candidate_hash)
  @last_run = latest_results.first&.analyzed_at
  
  # If no database results, fallback to cache
  if @candidates.empty?
    cache_key = "swing_screener_results_#{Date.current}"
    @candidates = Rails.cache.read(cache_key) || []
  end
end
```

---

## 🎯 Key Behaviors

### ✅ What Continues (Unchanged)

1. **Worker Process**
   - Job continues executing
   - Database updates continue
   - ActionCable broadcasts continue

2. **ActionCable Subscription**
   - Global subscription persists across pages
   - Receives broadcasts even on other pages
   - JavaScript checks page before updating UI

3. **Database**
   - ScreenerResult records keep being created
   - ScreenerRun status keeps updating
   - All updates are immediately available

### ⚠️ What Stops (Page-Specific)

1. **Polling JavaScript**
   - `setInterval` stops when you leave the page
   - This is fine - ActionCable handles updates

2. **Progressive Results Display**
   - Only updates if you're on the screener page
   - When you return, you see the latest state

---

## 📊 Example Timeline

```
Time  Action                          What Happens
─────────────────────────────────────────────────────────────────
00:00 User clicks "Run Screener"     Job enqueued, polling starts
00:05 User navigates to Positions    Polling stops, ActionCable still active
00:10 Job processing (50/100)       Worker updates DB, broadcasts sent
00:15 User still on Positions        Broadcasts received but UI doesn't update
00:20 Job completes                  Worker marks job complete, broadcasts final update
00:25 User returns to Screener       Controller reads DB, shows final results
```

---

## 🔍 Technical Details

### Global ActionCable Subscription

**Setup (in dashboard layout):**
```erb
<!-- app/views/layouts/dashboard.html.erb -->
<body data-controller="dashboard" data-dashboard-channel-value="DashboardChannel">
```

**JavaScript (persists across pages):**
```javascript
// app/javascript/controllers/dashboard_controller.js
connect() {
  // Connect to ActionCable (global, persists across navigation)
  if (this.channelValue) {
    this.connectToChannel();
  }
}

connectToChannel() {
  this.consumer = createConsumer();
  this.subscription = this.consumer.subscriptions.create(
    { channel: "DashboardChannel" },
    {
      received: (data) => {
        // Handle updates (checks page before updating UI)
        if (data.type === "screener_complete") {
          if (window.location.pathname.includes("screener")) {
            window.location.reload();
          }
        }
      }
    }
  );
}
```

### Page-Specific Polling

**Setup (only on screener page):**
```javascript
// app/views/dashboard/swing_screener.html.erb
const pollForResults = setInterval(() => {
  fetch('/dashboard/check_screener_results?type=swing')
    .then(response => response.json())
    .then(data => {
      // Update UI with latest results
    });
}, 5000);

// When you navigate away, this interval is cleared
// When you return, a new interval starts if job is still running
```

---

## ✅ What You'll See

### When You Return to Screener Page

**If Job Completed:**
- ✅ Shows final results immediately (read from database)
- ✅ Shows completion timestamp
- ✅ Shows all candidates found

**If Job Still Running:**
- ✅ Shows partial results (if any found so far)
- ✅ Shows progress: "Processing: 50/100 instruments..."
- ✅ Polling resumes automatically
- ✅ Updates continue in real-time

**If Job Failed:**
- ✅ Shows error message
- ✅ Shows last successful run (if any)
- ✅ Allows you to run again

---

## 🚀 Best Practices

### For Users

1. **You can navigate freely** - Jobs continue running in background
2. **Return anytime** - You'll see the latest results
3. **No need to wait** - Web server stays responsive

### For Developers

1. **Always use `perform_later`** - Never block the web process
2. **Persist results to database** - Not just cache
3. **Use ActionCable for real-time** - But handle navigation gracefully
4. **Read from database on page load** - Always show latest state

---

## 🔧 Current Implementation Status

### ✅ Working Correctly

- ✅ Jobs continue running when you navigate away
- ✅ Database updates persist
- ✅ ActionCable subscription persists globally
- ✅ Returning to page shows latest results
- ✅ Polling resumes if job still running

### 🎯 Potential Enhancements

1. **Notification Badge**
   - Show badge on screener link when job completes
   - Update: "Screener completed - 25 candidates found"

2. **Toast Notifications**
   - Show toast when job completes (even on other pages)
   - "Swing screener completed: 25 candidates found"

3. **Progress Indicator**
   - Show progress in sidebar or header
   - "Screener running: 50/100 processed"

---

## 📝 Summary

**✅ Jobs continue running when you navigate away**

**✅ Database updates continue (persisted)**

**✅ ActionCable subscription persists (global)**

**✅ Returning to page shows latest results**

**✅ No data loss or blocking**

**✅ Web server stays responsive**

---

**Status:** ✅ Working correctly - Navigation doesn't affect job execution

**Last Updated:** After verifying ActionCable global subscription behavior
