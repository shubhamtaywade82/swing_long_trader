# Active LTP Data Flow & Architecture

This document describes the **current active path** for Last Traded Price (LTP) data flow, WebSocket connections, and caching mechanisms in the system.

## Overview

The system uses a **broker-style architecture** with Redis Pub/Sub to efficiently distribute real-time market data from a single WebSocket connection to multiple Rails instances and thousands of browser clients.

## Complete Data Flow Path

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         REAL-TIME UPDATE PATH                            │
└─────────────────────────────────────────────────────────────────────────┘

1. DhanHQ WebSocket Feed
   │
   │ (Single persistent connection, up to 5,000 instruments)
   ▼
2. WebSocket Worker (SolidQueue Job Process)
   │ Location: app/jobs/market_hub/websocket_tick_streamer_job.rb
   │ Service: app/services/market_hub/websocket_tick_streamer.rb
   │
   │ On tick received:
   │   a) Cache LTP in Redis: SETEX ltp:SEGMENT:SECURITY_ID 30 <price>
   │   b) Publish to Redis Pub/Sub: PUBLISH live_ltp_updates <JSON>
   │
   ▼
3. Redis Cache & Pub/Sub
   │ Cache Key: ltp:SEGMENT:SECURITY_ID (TTL: 30 seconds)
   │ Pub/Sub Channel: live_ltp_updates
   │
   ▼
4. Redis Pub/Sub Listener (Rails Process - Background Thread)
   │ Location: app/services/market_hub/ltp_pubsub_listener.rb
   │ Initializer: config/initializers/ltp_pubsub_listener.rb
   │
   │ Subscribes to: live_ltp_updates channel
   │ Broadcasts via: ActionCable.server.broadcast("dashboard_updates", data)
   │
   ▼
5. ActionCable WebSocket (Rails → Browser)
   │ Channel: dashboard_updates
   │ Message Type: screener_ltp_update
   │
   ▼
6. Browser JavaScript (Frontend)
   │ Location: app/javascript/controllers/dashboard_controller.js
   │ Method: handleScreenerStream() → updateScreenerLtp()
   │
   │ Updates DOM: .js-ltp-cell[data-instrument-key] elements
   │ Visual feedback: Flash animation on price change
   │
   ▼
7. User sees updated price in UI
```

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      INITIAL PAGE LOAD PATH                             │
└─────────────────────────────────────────────────────────────────────────┘

1. Browser loads screener page
   │ Location: app/views/screeners/swing.html.erb
   │           app/views/screeners/longterm.html.erb
   │
   │ JavaScript:
   │   a) Collects instrument keys from HTML: data-instrument-key attributes
   │   b) Calls: POST /screeners/ltp/start (starts WebSocket worker)
   │   c) Starts polling: GET /api/v1/current_prices?keys=...
   │
   ▼
2. API Endpoint (Bulk LTP Retrieval)
   │ Location: app/controllers/api/v1/current_prices_controller.rb
   │ Route: GET /api/v1/current_prices?keys=NSE_EQ:1333,NSE_EQ:11536
   │
   │ Process:
   │   a) Build Redis keys: ["ltp:NSE_EQ:1333", "ltp:NSE_EQ:11536", ...]
   │   b) Redis MGET: Fetch all LTPs in single round trip
   │   c) For missing keys: Fallback to DhanHQ REST API
   │   d) Cache fetched values: SETEX ltp:KEY 30 <price>
   │
   ▼
3. Browser receives JSON response
   │ {
   │   "prices": { "NSE_EQ:1333": 1234.56, ... },
   │   "cached_count": 2,
   │   "api_fetched_count": 0
   │ }
   │
   ▼
4. JavaScript updates DOM
   │ Function: updatePrices() in screener view
   │ Updates: .js-ltp-cell[data-instrument-key] elements
   │
   ▼
5. User sees initial prices
   │ Then subscribes to ActionCable for real-time updates
```

## Component Details

### 1. WebSocket Worker (SolidQueue Job)

**Location:**
- Job: `app/jobs/market_hub/websocket_tick_streamer_job.rb`
- Service: `app/services/market_hub/websocket_tick_streamer.rb`

**Responsibilities:**
- Maintains single persistent connection to DhanHQ WebSocket
- Subscribes to instruments (up to 5,000 per connection)
- Receives tick-by-tick market data
- **Caches LTPs to Redis** with key format: `ltp:SEGMENT:SECURITY_ID` (TTL: 30 seconds)
- **Publishes ticks to Redis Pub/Sub** channel: `live_ltp_updates`

**Key Code:**
```ruby
# app/services/market_hub/websocket_tick_streamer.rb (lines 233-264)
def handle_tick(tick_data)
  # Cache LTP in Redis
  cache_key = "ltp:#{segment}:#{security_id}"
  redis_client.setex(cache_key, 30, ltp.to_f.to_s)

  # Publish to Redis Pub/Sub
  pubsub_channel = "live_ltp_updates"
  broadcast_data = {
    type: "screener_ltp_update",
    symbol: instrument.symbol_name,
    instrument_id: instrument.id,
    ltp: ltp.to_f,
    segment: segment,
    security_id: security_id.to_s,
    # ... other fields
  }
  redis_client.publish(pubsub_channel, broadcast_data.to_json)
end
```

**Process:**
- Runs in SolidQueue worker process (separate from Puma web server)
- Started via: `POST /screeners/ltp/start` (from screener page JavaScript)
- Thread-based: WebSocket connection runs in separate thread
- Auto-reconnection: Handled by dhanhq-client gem

### 2. Redis Cache

**Cache Keys:**
- Format: `ltp:SEGMENT:SECURITY_ID`
- Example: `ltp:NSE_EQ:1333`
- TTL: 30 seconds
- Purpose: Fast bulk retrieval via MGET for initial page load

**Pub/Sub Channel:**
- Channel: `live_ltp_updates`
- Purpose: Distribute real-time ticks to multiple Rails instances
- Message Format: JSON string with LTP update data

**Redis Client:**
- Primary: Direct Redis connection (`Redis.new(url: ENV["REDIS_URL"])`)
- Fallback: `Rails.cache.redis` if Redis gem available
- Fallback: `Rails.cache` (doesn't support MGET, but works)

### 3. Redis Pub/Sub Listener

**Location:**
- Service: `app/services/market_hub/ltp_pubsub_listener.rb`
- Initializer: `config/initializers/ltp_pubsub_listener.rb`

**Responsibilities:**
- Subscribes to Redis Pub/Sub channel (`live_ltp_updates`)
- Receives tick updates from WebSocket worker
- Broadcasts updates via ActionCable to all connected clients
- Runs in background thread (doesn't block Rails)

**Key Code:**
```ruby
# app/services/market_hub/ltp_pubsub_listener.rb (lines 130-142)
def handle_message(message)
  data = JSON.parse(message)
  # Broadcast via ActionCable
  ActionCable.server.broadcast("dashboard_updates", data)
end
```

**Process:**
- Automatically starts on Rails boot (via initializer)
- Runs in background thread: `Thread.new { subscribe_to_channel }`
- Graceful shutdown: Registered in `at_exit` handler
- Multiple instances: Each Rails instance has its own listener

### 4. ActionCable Broadcasting

**Channel:** `dashboard_updates`

**Message Format:**
```json
{
  "type": "screener_ltp_update",
  "symbol": "RELIANCE",
  "instrument_id": 123,
  "ltp": 2500.50,
  "timestamp": "2024-01-01T12:00:00Z",
  "source": "websocket",
  "segment": "NSE_EQ",
  "security_id": "1333"
}
```

**Broadcasting:**
- Location: `app/services/market_hub/ltp_pubsub_listener.rb` (line 136)
- Method: `ActionCable.server.broadcast("dashboard_updates", data)`
- Reaches: All browsers connected to ActionCable WebSocket

### 5. Frontend JavaScript

**ActionCable Subscription:**
- Location: `app/javascript/controllers/dashboard_controller.js`
- Channel: `dashboard_updates` (configured via `data-channel-value`)
- Handler: `handleScreenerStream(data)` (line 111)

**Real-Time Update Handler:**
```javascript
// app/javascript/controllers/dashboard_controller.js (lines 113-158)
if (data.type === "screener_ltp_update") {
  this.updateScreenerLtp(data.symbol, data.instrument_id, data.ltp);
}
```

**DOM Update:**
- Finds cells: `.js-ltp-cell[data-instrument-key]` matching instrument key
- Updates price: Sets cell text content to new LTP
- Visual feedback: Flash animation on price change
- Color coding: Green for up, red for down

**Polling Fallback:**
- Location: `app/views/screeners/swing.html.erb` (lines 646-698)
- Function: `startLtpPolling()`
- Interval: 1.5 seconds
- Endpoint: `GET /api/v1/current_prices?keys=...`
- Purpose: Fallback if ActionCable unavailable, or for initial load

### 6. High-Performance API Endpoint

**Location:** `app/controllers/api/v1/current_prices_controller.rb`

**Route:** `GET /api/v1/current_prices?keys=NSE_EQ:1333,NSE_EQ:11536`

**Process:**
1. Parse keys from query string or POST body
2. Build Redis keys: `["ltp:NSE_EQ:1333", "ltp:NSE_EQ:11536", ...]`
3. **Redis MGET**: Fetch all LTPs in single round trip (optimal performance)
4. For missing keys: Fallback to `DhanHQ::Models::MarketFeed.ltp` API
5. Cache fetched values: `SETEX ltp:KEY 30 <price>`
6. Return JSON with prices hash

**Response:**
```json
{
  "prices": {
    "NSE_EQ:1333": 1234.56,
    "NSE_EQ:11536": 5678.90
  },
  "timestamp": "2024-01-01T12:00:00Z",
  "count": 2,
  "cached_count": 2,
  "api_fetched_count": 0
}
```

**Performance:**
- **MGET**: Single Redis round trip for bulk retrieval
- **Fallback**: REST API only for missing keys
- **Caching**: Fetched values cached for 30 seconds

## Caching Strategy

### Redis Cache (Primary)

**Key Format:** `ltp:SEGMENT:SECURITY_ID`
- Example: `ltp:NSE_EQ:1333`
- TTL: 30 seconds
- Set by: WebSocket worker on each tick
- Read by: API endpoint via MGET

**Benefits:**
- Fast bulk retrieval (MGET)
- Single round trip for multiple keys
- Real-time data (updated every tick)

### Fallback Caching

**When Redis cache miss:**
1. API endpoint calls `DhanHQ::Models::MarketFeed.ltp`
2. Fetches missing LTPs from REST API
3. Caches fetched values: `SETEX ltp:KEY 30 <price>`
4. Returns to client

**Purpose:**
- Handles initial load before WebSocket starts
- Handles instruments not subscribed to WebSocket
- Graceful degradation

## WebSocket Connection Lifecycle

### Starting Connection

1. **Frontend:** JavaScript on screener page calls `POST /screeners/ltp/start`
2. **Controller:** `app/controllers/screeners_controller.rb#start_ltp_updates`
   - Validates parameters
   - Checks for duplicate streams (PostgreSQL advisory lock)
   - Enqueues job: `MarketHub::WebsocketTickStreamerJob.perform_later(...)`
3. **Job:** `app/jobs/market_hub/websocket_tick_streamer_job.rb`
   - Creates WebSocket thread
   - Initializes `MarketHub::WebsocketTickStreamer`
4. **Service:** `app/services/market_hub/websocket_tick_streamer.rb`
   - Connects to DhanHQ WebSocket
   - Subscribes to instruments
   - Starts receiving ticks

### Maintaining Connection

- **Heartbeat:** Updated every 30 seconds in Redis (`market_stream:heartbeat`)
- **Reconnection:** Handled automatically by dhanhq-client gem
- **Error Handling:** Logs errors, continues running

### Stopping Connection

- **Automatic:** When market closes (9:15 AM - 3:30 PM IST)
- **Manual:** Via `POST /screeners/ltp/stop` endpoint
- **Error:** On persistent connection failure (with retry)

## Data Flow Summary

### Real-Time Path (Primary)
```
DhanHQ WS → WebSocket Worker → Redis Cache + Pub/Sub → Pub/Sub Listener → ActionCable → Browser
```

**Latency:** < 1 second (real-time push)
**Efficiency:** Push model (no polling overhead)
**Scalability:** One WebSocket serves all users

### Initial Load Path (Fallback)
```
Browser → API Endpoint → Redis MGET → (Cache Miss) → DhanHQ REST API → Cache → Browser
```

**Latency:** ~100-500ms (HTTP request)
**Efficiency:** Bulk retrieval (MGET)
**Purpose:** Initial page load, fallback if WebSocket unavailable

### Polling Path (Fallback)
```
Browser → Poll API every 1.5s → Redis MGET → Browser
```

**Latency:** 1.5 seconds (polling interval)
**Efficiency:** Less efficient than push, but reliable
**Purpose:** Fallback if ActionCable unavailable

## Key Configuration

### Environment Variables

```bash
# Required: Enable WebSocket
export DHANHQ_WS_ENABLED=true

# Required: Redis connection
export REDIS_URL=redis://localhost:6379/0

# Optional: WebSocket mode (ticker, quote, full)
export DHANHQ_WS_MODE=quote
```

### Redis Keys & Channels

**Cache Keys:**
- `ltp:SEGMENT:SECURITY_ID` - LTP cache (TTL: 30 seconds)
- `market_stream:heartbeat` - Service heartbeat (TTL: 60 seconds)
- `websocket_stream:KEY` - Stream tracking (TTL: 1 hour)

**Pub/Sub Channels:**
- `live_ltp_updates` - Redis Pub/Sub channel for tick distribution

### ActionCable Channels

**Channel:** `dashboard_updates`
**Message Types:**
- `screener_ltp_update` - Single LTP update
- `screener_ltp_batch_update` - Multiple LTP updates
- Other types: `screener_progress`, `screener_complete`, etc.

## Performance Characteristics

### Real-Time Updates
- **Latency:** < 1 second from tick to browser
- **Throughput:** Handles thousands of ticks per second
- **Scalability:** One WebSocket connection serves unlimited users

### Bulk Retrieval (API)
- **MGET Performance:** Single round trip for N keys
- **Typical Latency:** 10-50ms for 100 keys
- **Fallback Latency:** 100-500ms if REST API needed

### Memory Usage
- **Redis Cache:** ~50 bytes per LTP (key + value)
- **1000 instruments:** ~50 KB
- **TTL:** 30 seconds (auto-expires)

## Troubleshooting

### No Real-Time Updates

1. **Check WebSocket Worker:**
   ```bash
   curl http://localhost:3000/api/v1/health/market_stream
   ```

2. **Check Redis Pub/Sub:**
   ```bash
   redis-cli PUBSUB CHANNELS
   # Should show: live_ltp_updates
   ```

3. **Check Rails Listener:**
   ```bash
   tail -f log/development.log | grep LtpPubSubListener
   ```

4. **Check ActionCable:**
   - Browser DevTools → Network → WS
   - Verify WebSocket connection to `/cable`

### Cache Misses

1. **Check Redis keys:**
   ```bash
   redis-cli KEYS "ltp:*"
   ```

2. **Check TTL:**
   ```bash
   redis-cli TTL "ltp:NSE_EQ:1333"
   # Should be > 0 and < 30
   ```

3. **Check WebSocket is running:**
   ```bash
   curl http://localhost:3000/api/v1/health/market_stream
   ```

## References

- [Broker-Style Architecture](./BROKER_STYLE_ARCHITECTURE.md)
- [Real-Time LTP Streaming](./REAL_TIME_LTP_STREAMING.md)
- [Instrument Subscription Flow](./INSTRUMENT_SUBSCRIPTION_FLOW.md)
- [Market Data LTP Access](./MARKET_DATA_LTP_ACCESS.md)
