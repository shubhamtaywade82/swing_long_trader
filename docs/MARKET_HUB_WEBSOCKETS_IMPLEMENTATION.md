# Market Hub WebSockets for Screener Real-Time LTP Updates

## Overview

This implementation adds real-time Last Traded Price (LTP) updates for screener shortlisted stocks using ActionCable WebSockets. The system polls market data during trading hours and broadcasts updates to connected clients, providing live price updates without page refreshes.

## Architecture

### Components

1. **MarketHub::LtpBroadcaster** (`app/services/market_hub/ltp_broadcaster.rb`)
   - Service that fetches LTPs for screener stocks using DhanHQ REST API
   - Broadcasts updates via ActionCable to connected clients
   - Handles batching to avoid API rate limits

2. **MarketHub::LtpPollerJob** (`app/jobs/market_hub/ltp_poller_job.rb`)
   - Background job that polls LTPs every 5 seconds during market hours
   - Automatically stops when market closes
   - Reschedules itself while market is open

3. **DashboardController Actions**
   - `start_ltp_updates`: Starts LTP polling for screener stocks
   - `stop_ltp_updates`: Stops LTP updates (automatic on market close)

4. **Frontend JavaScript**
   - Auto-starts LTP updates when screener page loads (if market is open)
   - Handles ActionCable messages for LTP updates
   - Updates table cells with live prices and visual indicators

## How It Works

### Flow

1. **Page Load**: When a screener page loads, JavaScript automatically detects if market is open and starts LTP updates
2. **Job Scheduling**: `LtpPollerJob` is enqueued with instrument IDs from screener results
3. **Polling**: Job runs every 5 seconds, fetching LTPs via `LtpBroadcaster`
4. **Broadcasting**: Updates are broadcast via ActionCable to `dashboard_updates` channel
5. **UI Updates**: JavaScript receives updates and refreshes price cells in screener tables

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
// Start LTP updates for swing screener
startLtpUpdates('swing');

// Start for longterm screener
startLtpUpdates('longterm');
```

### API Endpoints

```ruby
# Start LTP updates
POST /screeners/ltp/start
Body: {
  screener_type: "swing" | "longterm",
  instrument_ids: "1,2,3,4,5",  # Optional: comma-separated IDs
  symbols: "RELIANCE,TCS,INFY"   # Optional: comma-separated symbols
}

# Stop LTP updates (automatic on market close)
POST /screeners/ltp/stop
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

## Future Enhancements

1. **WebSocket Support**: If DhanHQ adds WebSocket support, migrate from polling
2. **Caching**: Cache LTPs to reduce API calls
3. **Selective Updates**: Only update visible rows
4. **Price Alerts**: Add alerts for significant price movements
5. **Historical Tracking**: Track price changes over time

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
