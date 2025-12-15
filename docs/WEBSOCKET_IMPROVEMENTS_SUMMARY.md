# WebSocket Job Scheduling Improvements Summary

## Overview

Comprehensive improvements to WebSocket job scheduling to ensure proper operation across multiple processes, prevent duplicates, and provide robust monitoring.

## Key Improvements

### 1. Cross-Process Thread Tracking ✅

**Problem**: `@@active_threads` only worked within same process.

**Solution**: Use Rails.cache (SolidCache) for cross-process tracking.

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

**Benefits**:
- Works across multiple worker processes
- Heartbeat mechanism detects dead streams
- TTL-based cleanup for stale entries

### 2. Multi-Layer Deduplication ✅

**Problem**: Multiple jobs could be enqueued for same stream.

**Solution**: Three-layer deduplication:

1. **Frontend Layer**: Check if indicator exists before API call
2. **Controller Layer**: Check cache + SolidQueue for existing jobs
3. **Job Layer**: Check cache + in-process threads before creating thread

**Flow**:
```
Frontend → Check indicator → Skip if exists
    ↓
Controller → Check cache → Check SolidQueue → Enqueue if not exists
    ↓
Job → Check cache → Check threads → Create thread if not exists
```

### 3. Health Check Job ✅

**New Job**: `WebsocketHealthCheckJob`

**Purpose**:
- Runs every 5 minutes during market hours
- Cleans up stale threads
- Monitors active stream count
- Logs health status

**Configuration** (`config/recurring.yml`):
```yaml
websocket_health_check:
  class: MarketHub::WebsocketHealthCheckJob
  schedule: "*/5 * * * 1-5" # Every 5 minutes, Mon-Fri
```

### 4. Improved Thread Management ✅

**New Methods**:
- `stream_running?(stream_key, cache_key)` - Cross-process check
- `mark_stream_running(stream_key, cache_key)` - Mark as running
- `refresh_stream_heartbeat(cache_key)` - Update heartbeat
- `mark_stream_stopped(stream_key, cache_key)` - Clean up
- `cleanup_stale_streams()` - Remove dead threads
- `stream_status(stream_key)` - Get detailed status

**Thread Lifecycle**:
1. Mark as "starting" (short TTL, prevents race conditions)
2. Create thread
3. Mark as "running" (with heartbeat)
4. Refresh heartbeat every 30 seconds
5. Mark as "stopped" on cleanup

### 5. Better Controller Checks ✅

**Improved Methods**:
- `websocket_stream_running?(stream_key)` - Checks cache with heartbeat validation
- `find_existing_websocket_job(...)` - Better SolidQueue queries with time window

**Status Responses**:
- `already_running` - Stream is active (cache + heartbeat check)
- `queued` - Job already in queue
- `started` - New job enqueued

### 6. Frontend Improvements ✅

**Both Screener Pages**:
- Check for existing indicator before API call
- Handle `already_running` and `queued` statuses
- Show indicator even if stream already active

## Architecture

### Cross-Process Flow

```
┌─────────────────────────────────────────────────────────┐
│ Process 1: Web Server (Puma)                           │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Controller: Check cache → Check queue → Enqueue     │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│ Process 2: SolidQueue Worker 1                          │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Job: Check cache → Check threads → Create thread    │ │
│ │ Thread: WebSocket connection                         │ │
│ │ Cache: Write status + heartbeat                     │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│ Process 3: SolidQueue Worker 2                          │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Job: Check cache → Skip (already running)           │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│ Shared Cache (Rails.cache / SolidCache)                 │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Key: websocket_stream:type:swing|ids:1,2,3         │ │
│ │ Value: {status: "running", heartbeat: "...", ...}  │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Monitoring

### Health Check Logs

```
[WebsocketHealthCheckJob] Health check: 
  2 active threads (this process), 
  3 streams (cross-process), 
  1 stale streams cleaned
```

### Stream Status

```ruby
# In Rails console
MarketHub::WebsocketTickStreamerJob.stream_status("type:swing|ids:1,2,3")
# => {
#   thread_alive: true,
#   cache_exists: true,
#   cache_data: {status: "running", heartbeat: "2025-01-15T10:30:00Z", ...},
#   process_id: 12345
# }
```

### Active Stream Count

```ruby
# In-process threads
MarketHub::WebsocketTickStreamerJob.active_stream_count
# => 2

# Cross-process (approximate)
MarketHub::WebsocketTickStreamerJob.active_streams_count_cross_process
# => 3
```

## Configuration

### Environment Variables

```bash
# Enable WebSocket
export DHANHQ_WS_ENABLED=true

# Set mode (:ticker, :quote, :full)
export DHANHQ_WS_MODE=quote  # default: quote
```

### Recurring Jobs

Health check runs automatically via `config/recurring.yml`:
- Schedule: Every 5 minutes during market hours (Mon-Fri)
- Purpose: Cleanup stale streams, monitor health

## Testing

### Manual Testing

1. **Start Stream**:
   ```ruby
   MarketHub::WebsocketTickStreamerJob.perform_later(
     screener_type: "swing",
     instrument_ids: "1,2,3"
   )
   ```

2. **Check Status**:
   ```ruby
   MarketHub::WebsocketTickStreamerJob.stream_status("type:swing|ids:1,2,3")
   ```

3. **Stop All Streams**:
   ```ruby
   MarketHub::WebsocketTickStreamerJob.stop_all_streams
   ```

4. **Cleanup Stale**:
   ```ruby
   MarketHub::WebsocketTickStreamerJob.cleanup_stale_streams
   ```

## Benefits

1. ✅ **No Duplicates**: Multi-layer deduplication prevents duplicate streams
2. ✅ **Multi-Process**: Works correctly across multiple worker processes
3. ✅ **Automatic Cleanup**: Health check job cleans up stale streams
4. ✅ **Better Monitoring**: Status methods and health checks
5. ✅ **Race Condition Safe**: Cache-based locking prevents race conditions
6. ✅ **Graceful Shutdown**: Proper cleanup on application exit

## Files Changed

- `app/jobs/market_hub/websocket_tick_streamer_job.rb` - Added cross-process tracking
- `app/jobs/market_hub/websocket_health_check_job.rb` - New health check job
- `app/controllers/dashboard_controller.rb` - Improved job checking
- `app/views/dashboard/swing_screener.html.erb` - Frontend deduplication
- `app/views/dashboard/longterm_screener.html.erb` - Frontend deduplication
- `config/recurring.yml` - Added health check schedule

## References

- Implementation: `app/jobs/market_hub/websocket_tick_streamer_job.rb`
- Health Check: `app/jobs/market_hub/websocket_health_check_job.rb`
- Controller: `app/controllers/dashboard_controller.rb`
- Architecture: `docs/WEBSOCKET_THREAD_ARCHITECTURE.md`
