# Instrument Subscription Flow

This document explains how instruments are subscribed to the WebSocket feed in the broker-style architecture.

## Overview

The subscription process follows this flow:

```
Frontend (Browser) → Controller → WebSocket Job → WebSocket Service → DhanHQ WebSocket
```

## Step-by-Step Subscription Process

### 1. Frontend Initiates Subscription

**Location:** `app/views/screeners/swing.html.erb` and `app/views/screeners/longterm.html.erb`

When a screener page loads, JavaScript automatically:

1. **Collects Instrument IDs** from the HTML table:
   ```javascript
   const rows = document.querySelectorAll('tr[data-screener-instrument-id]');
   const instrumentIds = Array.from(rows)
     .map(row => row.getAttribute('data-screener-instrument-id'))
     .filter(id => id && id !== 'null')
     .slice(0, 200); // Limit to 200 stocks
   ```

2. **Sends POST Request** to start LTP updates:
   ```javascript
   fetch('/screeners/ltp/start', {
     method: 'POST',
     body: JSON.stringify({
       screener_type: 'swing',  // or 'longterm'
       instrument_ids: instrumentIds.join(','),
       websocket: 'true'
     })
   })
   ```

**Key Points:**
- Instruments are extracted from the rendered HTML table
- Maximum 200 instruments per subscription (to avoid overwhelming the WebSocket)
- Only instruments with valid `data-screener-instrument-id` attributes are included

### 2. Controller Processes Request

**Location:** `app/controllers/screeners_controller.rb#start_ltp_updates`

The controller:

1. **Parses Parameters:**
   ```ruby
   screener_type = validate_screener_type(params[:screener_type])
   instrument_ids = parse_instrument_ids(params[:instrument_ids])  # "1,2,3" → [1, 2, 3]
   symbols = parse_symbols(params[:symbols])  # Optional fallback
   ```

2. **Validates Input:**
   - Ensures at least one identifier (instrument_ids or symbols) is provided
   - Validates screener_type is "swing" or "longterm"

3. **Checks for Existing Stream:**
   - Uses PostgreSQL advisory lock to prevent race conditions
   - Checks if WebSocket stream is already running for this combination
   - Checks if job is already queued

4. **Enqueues WebSocket Job:**
   ```ruby
   MarketHub::WebsocketTickStreamerJob.perform_later(
     screener_type: screener_type,
     instrument_ids: instrument_ids.join(","),  # Convert array to comma-separated string
     symbols: symbols.join(",")  # Optional
   )
   ```

### 3. WebSocket Job Processes Subscription

**Location:** `app/jobs/market_hub/websocket_tick_streamer_job.rb`

The job:

1. **Creates Unique Stream Key:**
   ```ruby
   stream_key = stream_key(screener_type, instrument_ids, symbols)
   # Example: "type:swing|ids:1,2,3|symbols:RELIANCE,TCS"
   ```

2. **Checks for Duplicate Streams:**
   - Uses Redis cache to check if stream is already running (cross-process check)
   - Prevents duplicate subscriptions

3. **Starts WebSocket Thread:**
   ```ruby
   websocket_thread = Thread.new do
     streamer = MarketHub::WebsocketTickStreamer.new(
       instrument_ids: instrument_ids,
       symbols: symbols
     )
     streamer.call  # Starts WebSocket connection
   end
   ```

### 4. WebSocket Service Determines Instruments

**Location:** `app/services/market_hub/websocket_tick_streamer.rb#fetch_instruments`

The service determines which instruments to subscribe to using this priority:

#### Priority 1: Explicit Instrument IDs
```ruby
if @instrument_ids.any?
  Instrument.where(id: @instrument_ids)
```

#### Priority 2: Explicit Symbols
```ruby
elsif @symbols.any?
  Instrument.where(symbol_name: @symbols)
```

#### Priority 3: Latest Screener Results (Fallback)
```ruby
else
  # Default: get latest screener results
  latest_results = ScreenerResult.latest_for(screener_type: "swing", limit: 200)
  instrument_ids = latest_results.pluck(:instrument_id).compact.uniq
  Instrument.where(id: instrument_ids)
end
```

**Note:** `ScreenerResult.latest_for` returns the most recent screener results for the given type, ordered by score (descending).

### 5. WebSocket Service Subscribes to Instruments

**Location:** `app/services/market_hub/websocket_tick_streamer.rb#subscribe_to_ticks`

For each instrument, the service:

1. **Formats Subscription Parameters:**
   ```ruby
   subscription_params = {
     ExchangeSegment: instrument.exchange_segment,  # e.g., "NSE_EQ"
     SecurityId: instrument.security_id.to_s        # e.g., "1333"
   }
   @subscriptions << subscription_params
   ```

2. **Subscribes via DhanHQ WebSocket Client:**
   ```ruby
   @websocket_client.subscribe_one(
     segment: segment,        # e.g., "NSE_EQ"
     security_id: security_id # e.g., "1333"
   )
   ```

**Key Points:**
- DhanHQ WebSocket supports up to **5,000 instruments per connection**
- The client automatically chunks subscriptions (up to 100 per SUB message)
- Each subscription uses `segment` (exchange) and `security_id` (instrument ID)

## Instrument Sources

### Source 1: Frontend HTML Table (Primary)

**How it works:**
- Screener results are rendered in HTML table with `data-screener-instrument-id` attributes
- JavaScript extracts these IDs from the DOM
- IDs are sent to the controller

**Example HTML:**
```html
<tr data-screener-instrument-id="123">
  <td>RELIANCE</td>
  <td>₹2,500</td>
</tr>
```

### Source 2: Latest Screener Results (Fallback)

**How it works:**
- If no instrument_ids or symbols are provided, the service queries the database
- Uses `ScreenerResult.latest_for(screener_type: "swing", limit: 200)`
- Gets the most recent screener run results, ordered by score

**Database Query:**
```ruby
# app/models/screener_result.rb
def self.latest_for(screener_type:, limit: nil)
  latest_analyzed_at = where(screener_type: screener_type).maximum(:analyzed_at)
  return [] unless latest_analyzed_at

  scope = where(screener_type: screener_type, analyzed_at: latest_analyzed_at)
          .order(score: :desc)
  scope = scope.limit(limit) if limit
  scope
end
```

## Subscription Limits

### Per Connection Limit
- **DhanHQ WebSocket:** Up to 5,000 instruments per connection
- **Application Limit:** 200 instruments per subscription (configurable)

### Why Limit to 200?

1. **Performance:** Prevents overwhelming the WebSocket connection
2. **UI Usability:** Most screeners show top 20-50 results
3. **Memory:** Reduces Redis cache size
4. **Rate Limits:** Avoids hitting DhanHQ rate limits

## Subscription Management

### Preventing Duplicate Subscriptions

The system uses multiple mechanisms to prevent duplicate subscriptions:

1. **PostgreSQL Advisory Lock:**
   ```ruby
   lock_key = Digest::MD5.hexdigest("websocket_stream_#{stream_key}").to_i(16) % (2**31)
   lock_result = ActiveRecord::Base.connection.execute(
     "SELECT pg_try_advisory_lock(#{lock_key}) AS acquired"
   )
   ```

2. **Redis Cache Check:**
   ```ruby
   cache_key = "websocket_stream:#{stream_key}"
   if stream_running?(stream_key, cache_key)
     return  # Stream already running
   end
   ```

3. **Job Queue Check:**
   ```ruby
   existing_job = find_existing_websocket_job(screener_type, instrument_ids, symbols)
   if existing_job
     return  # Job already queued
   end
   ```

### Stream Key Format

The stream key uniquely identifies a subscription:

```
"type:swing|ids:1,2,3|symbols:RELIANCE,TCS"
```

This allows:
- Multiple screener types (swing, longterm)
- Multiple instrument sets
- Cross-process deduplication

## Subscription Lifecycle

### Starting a Subscription

1. **Frontend:** Collects instrument IDs from HTML
2. **Controller:** Validates and enqueues job
3. **Job:** Creates WebSocket thread
4. **Service:** Fetches instruments and subscribes
5. **WebSocket:** Connects to DhanHQ and subscribes

### Stopping a Subscription

1. **Automatic:** When market closes (9:15 AM - 3:30 PM IST)
2. **Manual:** Via `stop_ltp_updates` endpoint (scheduled to stop when market closes)
3. **Error:** On WebSocket connection failure (with retry)

### Updating a Subscription

Currently, subscriptions are **static** - they don't update dynamically. To change instruments:

1. Stop the current subscription
2. Start a new subscription with updated instrument list

**Future Enhancement:** Dynamic subscription updates (add/remove instruments without reconnecting)

## Example Flow

### Scenario: User loads Swing Screener page

1. **Page Load:**
   ```javascript
   // JavaScript extracts IDs from table
   const instrumentIds = [1, 2, 3, 4, 5]; // From HTML table
   ```

2. **POST Request:**
   ```http
   POST /screeners/ltp/start
   {
     "screener_type": "swing",
     "instrument_ids": "1,2,3,4,5",
     "websocket": "true"
   }
   ```

3. **Controller:**
   ```ruby
   instrument_ids = [1, 2, 3, 4, 5]
   MarketHub::WebsocketTickStreamerJob.perform_later(
     screener_type: "swing",
     instrument_ids: "1,2,3,4,5"
   )
   ```

4. **WebSocket Service:**
   ```ruby
   instruments = Instrument.where(id: [1, 2, 3, 4, 5])
   # Subscribes to each:
   # - NSE_EQ:1333 (RELIANCE)
   # - NSE_EQ:11536 (TCS)
   # - NSE_EQ:1594 (HDFCBANK)
   # - etc.
   ```

5. **DhanHQ WebSocket:**
   ```
   SUBSCRIBE NSE_EQ:1333
   SUBSCRIBE NSE_EQ:11536
   SUBSCRIBE NSE_EQ:1594
   ...
   ```

6. **Ticks Arrive:**
   ```
   TICK: NSE_EQ:1333 → LTP: ₹2,500.50
   → Cache: SETEX ltp:NSE_EQ:1333 30 2500.50
   → Pub/Sub: PUBLISH live_ltp_updates {...}
   → ActionCable: Broadcast to dashboard_updates
   → Browser: Updates UI
   ```

## Troubleshooting

### No Instruments Subscribed

1. **Check Frontend:**
   - Verify HTML table has `data-screener-instrument-id` attributes
   - Check browser console for JavaScript errors
   - Verify `startLtpUpdates()` is called

2. **Check Controller:**
   - Verify `instrument_ids` parameter is received
   - Check logs for validation errors
   - Verify job is enqueued

3. **Check WebSocket Service:**
   - Verify instruments are found in database
   - Check logs: `[MarketHub::WebsocketTickStreamer] Fetching instruments`
   - Verify subscription count matches instrument count

### Wrong Instruments Subscribed

1. **Check Instrument IDs:**
   - Verify IDs match screener results
   - Check for stale data in HTML table
   - Verify `ScreenerResult.latest_for` returns expected results

2. **Check Fallback Logic:**
   - If no IDs provided, service uses latest screener results
   - Verify screener has been run recently
   - Check `screener_type` matches expected type

### Subscription Limit Reached

1. **Reduce Instrument Count:**
   - Limit frontend to top N instruments (e.g., 50)
   - Use screener score to filter instruments

2. **Multiple Subscriptions:**
   - Split instruments across multiple WebSocket connections
   - Use different stream keys for different instrument sets

## References

- [Real-Time LTP Streaming Documentation](./REAL_TIME_LTP_STREAMING.md)
- [Broker-Style Architecture](./BROKER_STYLE_ARCHITECTURE.md)
- [WebSocket Thread Architecture](./WEBSOCKET_THREAD_ARCHITECTURE.md)
