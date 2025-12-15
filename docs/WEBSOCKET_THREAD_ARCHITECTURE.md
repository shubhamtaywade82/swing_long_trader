# WebSocket Thread Architecture

## Overview

The WebSocket connection for real-time tick streaming runs in a **separate thread** within the SolidQueue worker process to avoid blocking the job execution thread.

## Architecture

### Process Separation

```
┌─────────────────────────────────────────────────────────┐
│ Process 1: Web Server (Puma)                            │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Thread 1: HTTP Request Handler                      │ │
│ │ Thread 2: HTTP Request Handler                      │ │
│ │ Thread 3: ActionCable WebSocket (dashboard_updates) │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Process 2: SolidQueue Worker                           │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Thread 1: Job Execution (completes immediately)     │ │
│ │ Thread 2: Job Execution                             │ │
│ │ Thread 3: Job Execution                             │ │
│ │ Thread 4: Job Execution                             │ │
│ │ Thread 5: Job Execution                             │ │
│ │                                                     │ │
│ │ ┌───────────────────────────────────────────────┐ │ │
│ │ │ WebSocket Thread (separate)                    │ │ │
│ │ │ - Runs EventMachine event loop                 │ │ │
│ │ │ - Maintains DhanHQ WebSocket connection        │ │ │
│ │ │ - Handles tick callbacks                       │ │ │
│ │ │ - Stays alive until market closes              │ │ │
│ │ └───────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Thread Flow

1. **Job Thread** (SolidQueue worker thread):
   ```ruby
   def perform(...)
     # Create separate thread for WebSocket
     websocket_thread = Thread.new do
       # WebSocket connection runs here
       streamer = WebsocketTickStreamer.new(...)
       streamer.call
       # Thread stays alive, running EventMachine loop
     end
     
     # Job completes immediately
     # Thread continues running independently
   end
   ```

2. **WebSocket Thread**:
   - Runs EventMachine reactor loop
   - Maintains DhanHQ WebSocket connection
   - Handles incoming ticks
   - Broadcasts via ActionCable
   - Automatically stops when market closes

## Benefits

### ✅ Non-Blocking Job Execution

- Job thread completes immediately
- Doesn't tie up worker threads
- Other jobs can execute normally

### ✅ Proper Resource Management

- Thread is tracked in `@@active_threads` map
- Automatic cleanup when market closes
- Graceful shutdown support

### ✅ Error Handling

- Thread errors don't crash the job
- Automatic retry on failure
- Proper cleanup in `ensure` block

## Thread Lifecycle

### Start

```ruby
# Job enqueued
WebsocketTickStreamerJob.perform_later(...)

# Job executes
1. Creates thread
2. Thread starts WebSocket connection
3. Job completes immediately
4. Thread continues running
```

### Runtime

```ruby
# Thread runs EventMachine loop
while market_open?
  # EventMachine handles WebSocket events
  # Tick callbacks fire
  # ActionCable broadcasts sent
  sleep(5) # Check market status
end
```

### Stop

```ruby
# Market closes or error occurs
1. Thread detects market closed
2. Calls streamer.stop()
3. Unsubscribes from WebSocket
4. Closes connection gracefully
5. Thread exits
6. Removed from @@active_threads
```

## Thread Management

### Active Thread Tracking

```ruby
# Threads are stored in class variable
@@active_threads = Concurrent::Map.new

# Key format: "type:swing|ids:1,2,3|symbols:RELIANCE,TCS"
# Allows multiple streams for different screener types
```

### Cleanup Methods

```ruby
# Stop all active streams (graceful shutdown)
MarketHub::WebsocketTickStreamerJob.stop_all_streams

# Get active stream count
MarketHub::WebsocketTickStreamerJob.active_stream_count
```

## Configuration

### Thread Safety

- Uses `Concurrent::Map` for thread-safe storage
- Thread names are set for debugging
- `abort_on_exception = false` for graceful error handling

### Market Hours Check

- Thread checks market status every 5 seconds
- Automatically stops when market closes
- Prevents unnecessary resource usage

## Monitoring

### Logging

```ruby
# Thread start
[WebsocketTickStreamerJob] Starting WebSocket thread for key: type:swing|ids:1,2,3

# Thread running
[WebsocketTickStreamerJob] WebSocket started: 50 instruments subscribed

# Thread stop
[WebsocketTickStreamerJob] Market closed, stopping WebSocket stream
[WebsocketTickStreamerJob] WebSocket thread cleaned up
```

### Thread Status

Check active threads in Rails console:

```ruby
# Count active streams
MarketHub::WebsocketTickStreamerJob.active_stream_count

# List all threads
Thread.list.select { |t| t.name&.start_with?("WebSocketStreamer") }
```

## Error Handling

### Thread Errors

```ruby
rescue StandardError => e
  # Log error
  Rails.logger.error("WebSocket thread error: #{e.message}")
  
  # Retry if market still open
  if market_open?
    sleep(10)
    WebsocketTickStreamerJob.perform_later(...)
  end
ensure
  # Always cleanup
  streamer&.stop
  @@active_threads.delete(stream_key)
end
```

### Connection Errors

- EventMachine handles WebSocket reconnection automatically
- Exponential backoff built into dhanhq-client gem
- Subscription persistence on reconnect

## Best Practices

1. **Don't Block Job Thread**: Always run WebSocket in separate thread
2. **Track Threads**: Use thread-safe storage for active threads
3. **Cleanup Properly**: Always stop streamer and remove from tracking
4. **Handle Errors**: Catch exceptions and retry gracefully
5. **Monitor Resources**: Check thread count and memory usage

## Troubleshooting

### Thread Not Starting

- Check if market is open
- Verify WebSocket is enabled (`DHANHQ_WS_ENABLED=true`)
- Check logs for initialization errors

### Thread Not Stopping

- Verify market hours check is working
- Check if `streamer.stop` is being called
- Use `stop_all_streams` for forced cleanup

### Memory Leaks

- Ensure threads are removed from `@@active_threads`
- Check for EventMachine connection leaks
- Monitor thread count over time

## References

- Implementation: `app/jobs/market_hub/websocket_tick_streamer_job.rb`
- Service: `app/services/market_hub/websocket_tick_streamer.rb`
- dhanhq-client gem: https://github.com/shubhamtaywade82/dhanhq-client
