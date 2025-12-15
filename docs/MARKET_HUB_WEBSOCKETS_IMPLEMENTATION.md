# Market Hub WebSockets for Screener Real-Time LTP Updates

## Overview

This implementation adds real-time Last Traded Price (LTP) updates for screener shortlisted stocks using ActionCable WebSockets. The system polls market data during trading hours and broadcasts updates to connected clients, providing live price updates without page refreshes.

## Architecture

### Components

#### Polling-Based (Current Default - 5 Second Interval)

1. **MarketHub::LtpBroadcaster** (`app/services/market_hub/ltp_broadcaster.rb`)
   - Service that fetches LTPs for screener stocks using DhanHQ REST API
   - Broadcasts updates via ActionCable to connected clients
   - Handles batching to avoid API rate limits
   - **Update Frequency**: Every 5 seconds (not real-time)

2. **MarketHub::LtpPollerJob** (`app/jobs/market_hub/ltp_poller_job.rb`)
   - Background job that polls LTPs every 5 seconds during market hours
   - Automatically stops when market closes
   - Reschedules itself while market is open
   - **Limitation**: 5-second delay between updates

#### Real-Time WebSocket-Based (Optional - True Real-Time Ticks)

3. **MarketHub::WebsocketTickStreamer** (`app/services/market_hub/websocket_tick_streamer.rb`)
   - Service that connects to DhanHQ WebSocket market feed
   - Receives live ticks as they happen (true real-time)
   - Broadcasts ticks immediately via ActionCable
   - **Update Frequency**: Instant (as ticks arrive)

4. **MarketHub::WebsocketTickStreamerJob** (`app/jobs/market_hub/websocket_tick_streamer_job.rb`)
   - Background job that maintains WebSocket connection
   - Handles reconnection on errors
   - Stops automatically when market closes

3. **DashboardController Actions**
   - `start_ltp_updates`: Starts LTP polling for screener stocks
   - `stop_ltp_updates`: Stops LTP updates (automatic on market close)

4. **Frontend JavaScript**
   - Auto-starts LTP updates when screener page loads (if market is open)
   - Handles ActionCable messages for LTP updates
   - Updates table cells with live prices and visual indicators

## How It Works

### Polling Mode (Default - 5 Second Interval)

1. **Page Load**: When a screener page loads, JavaScript automatically detects if market is open and starts LTP updates
2. **Job Scheduling**: `LtpPollerJob` is enqueued with instrument IDs from screener results
3. **Polling**: Job runs every 5 seconds, fetching LTPs via `LtpBroadcaster` using REST API
4. **Broadcasting**: Updates are broadcast via ActionCable to `dashboard_updates` channel
5. **UI Updates**: JavaScript receives updates and refreshes price cells in screener tables
6. **Limitation**: 5-second delay between updates (not true real-time)

### WebSocket Mode (Optional - True Real-Time)

1. **Page Load**: JavaScript detects WebSocket availability and starts WebSocket stream
2. **Job Scheduling**: `WebsocketTickStreamerJob` is enqueued to maintain WebSocket connection
3. **WebSocket Connection**: Connects to DhanHQ market feed WebSocket
4. **Live Ticks**: Receives ticks as they happen (true real-time, no delay)
5. **Immediate Broadcasting**: Each tick is immediately broadcast via ActionCable
6. **UI Updates**: JavaScript receives updates instantly and refreshes price cells
7. **Advantage**: True real-time updates with no polling delay

### Market Hours Detection

- **Trading Hours**: Monday-Friday, 9:15 AM - 3:30 PM IST
- **Automatic Start**: Only starts during market hours
- **Automatic Stop**: Stops when market closes

## Usage

### Automatic (Recommended)

LTP updates start automatically when:
- Screener page loads
- Market is open (9:15 AM - 3:30 PM IST, Mon-Fri)
- Screener results exist

### Manual Start

```javascript
// Start LTP updates for swing screener (polling mode)
startLtpUpdates('swing');

// Start for longterm screener (polling mode)
startLtpUpdates('longterm');

// Start with WebSocket (true real-time) - requires WebSocket enabled
fetch('/screeners/ltp/start', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token },
  body: JSON.stringify({ screener_type: 'swing', websocket: true })
});
```

### API Endpoints

```ruby
# Start LTP updates (polling mode - default)
POST /screeners/ltp/start
Body: {
  screener_type: "swing" | "longterm",
  instrument_ids: "1,2,3,4,5",  # Optional: comma-separated IDs
  symbols: "RELIANCE,TCS,INFY",  # Optional: comma-separated symbols
  websocket: false  # false = polling (5 sec), true = WebSocket (real-time)
}

# Start LTP updates (WebSocket mode - true real-time)
POST /screeners/ltp/start
Body: {
  screener_type: "swing" | "longterm",
  instrument_ids: "1,2,3,4,5",
  websocket: true  # Enable WebSocket for real-time ticks
}

# Stop LTP updates (automatic on market close)
POST /screeners/ltp/stop
```

### Enabling WebSocket Mode

To use true real-time WebSocket ticks instead of polling:

1. **Set Environment Variable**:
   ```bash
   export DHANHQ_WS_ENABLED=true
   ```

2. **Or Update Config** (`config/initializers/dhanhq_config.rb`):
   ```ruby
   config.x.dhanhq = ActiveSupport::InheritableOptions.new(
     ws_enabled: true,  # Enable WebSocket for market feed
     order_ws_enabled: false,  # Keep order WebSocket disabled
   )
   ```

3. **Start with WebSocket flag**:
   ```javascript
   fetch('/screeners/ltp/start', {
     method: 'POST',
     body: JSON.stringify({ screener_type: 'swing', websocket: true })
   });
   ```

## Visual Indicators

### Status Indicator
- Green pulsing dot appears next to page title when LTP updates are active
- Indicates real-time updates are running

### Price Updates
- **Price Up**: Green color with flash animation
- **Price Down**: Red color with flash animation
- **Row Highlight**: Brief background highlight when price updates

## Configuration

### Poll Interval
Default: 5 seconds (configurable in `LtpPollerJob::POLL_INTERVAL`)

### Batch Size
Default: 50 instruments per batch (configurable in `LtpBroadcaster::BATCH_SIZE`)

### Rate Limiting
- Small delay (0.1s) between batches to avoid API rate limits
- Maximum 200 stocks per screener (configurable in JavaScript)

## ActionCable Messages

### Single LTP Update
```json
{
  "type": "screener_ltp_update",
  "symbol": "RELIANCE",
  "instrument_id": 123,
  "ltp": 2456.75,
  "timestamp": "2025-01-15T10:30:00Z"
}
```

### Batch LTP Update
```json
{
  "type": "screener_ltp_batch_update",
  "updates": [
    {
      "symbol": "RELIANCE",
      "instrument_id": 123,
      "ltp": 2456.75,
      "timestamp": "2025-01-15T10:30:00Z"
    },
    ...
  ],
  "timestamp": "2025-01-15T10:30:00Z"
}
```

## Error Handling

- **API Failures**: Logged but don't stop polling
- **Market Closed**: Automatically stops polling
- **No Results**: Skips start if no screener results found
- **Connection Issues**: ActionCable handles reconnection automatically

## Performance Considerations

1. **API Rate Limits**: Batched requests with delays
2. **Database Queries**: Efficient queries using `pluck` and `where`
3. **Broadcasting**: Batch updates reduce ActionCable overhead
4. **Frontend**: Debounced updates prevent UI jank

## Comparison: Polling vs WebSocket

| Feature | Polling Mode (Default) | WebSocket Mode (Optional) |
|---------|----------------------|--------------------------|
| **Update Frequency** | Every 5 seconds | Instant (as ticks arrive) |
| **Latency** | 0-5 seconds | < 100ms |
| **API Calls** | High (every 5 sec) | Low (one connection) |
| **Real-Time** | ❌ No (5 sec delay) | ✅ Yes (true real-time) |
| **Resource Usage** | Higher (REST API calls) | Lower (persistent connection) |
| **Setup** | Simple (default) | Requires WebSocket config |
| **Reliability** | High (stateless) | Medium (requires reconnection logic) |

## Improvements Made

### ✅ Cross-Process Thread Tracking
- Uses Rails.cache (SolidCache) for cross-process stream tracking
- Heartbeat mechanism (refreshed every 30 seconds)
- TTL-based expiration for stale streams
- Works across multiple worker processes

### ✅ Job Deduplication
- Frontend checks prevent duplicate API calls
- Controller checks for existing jobs/streams before enqueueing
- Returns appropriate status (`already_running`, `queued`)
- Prevents duplicate threads within same process

### ✅ Health Monitoring
- `WebsocketHealthCheckJob` runs every 5 minutes during market hours
- Automatically cleans up stale streams
- Monitors active stream count
- Logs health status

### ✅ Improved Error Handling
- Graceful thread shutdown
- Automatic retry on failure
- Proper cleanup in ensure blocks
- Cross-process status checking

## Future Enhancements

1. ✅ **WebSocket Support**: Implemented - can be enabled via config
2. ✅ **Cross-Process Tracking**: Implemented using Rails.cache
3. ✅ **Job Deduplication**: Implemented with multi-layer checks
4. ✅ **Health Monitoring**: Implemented with periodic cleanup
5. **Selective Updates**: Only update visible rows (performance optimization)
6. **Price Alerts**: Add alerts for significant price movements
7. **Historical Tracking**: Track price changes over time
8. **Hybrid Mode**: Use WebSocket when available, fallback to polling

## Testing

### Manual Testing

1. Open screener page during market hours
2. Verify green indicator appears
3. Check browser console for "LTP updates started" message
4. Watch price cells update in real-time
5. Verify price change animations

### Monitoring

- Check SolidQueue for `MarketHub::LtpPollerJob` entries
- Monitor ActionCable connections in browser DevTools
- Check Rails logs for LTP polling activity

## Troubleshooting

### LTP Updates Not Starting

1. **Check Market Hours**: Verify current time is within 9:15 AM - 3:30 PM IST, Mon-Fri
2. **Check Screener Results**: Ensure screener has been run and results exist
3. **Check Browser Console**: Look for JavaScript errors
4. **Check Rails Logs**: Verify job is being enqueued

### Prices Not Updating

1. **Check ActionCable Connection**: Verify connection status indicator
2. **Check Browser Console**: Look for ActionCable messages
3. **Check Network Tab**: Verify WebSocket connection is active
4. **Check Rails Logs**: Verify broadcasts are being sent

### Performance Issues

1. **Reduce Poll Interval**: Increase `POLL_INTERVAL` if needed
2. **Reduce Batch Size**: Decrease `BATCH_SIZE` if API rate limits hit
3. **Limit Stocks**: Reduce maximum stocks per screener

## Notes

- Uses REST API (not WebSocket) as per swing trading architecture
- Compatible with existing ActionCable infrastructure
- Non-intrusive: Works alongside existing screener functionality
- Automatic cleanup: Stops when market closes
