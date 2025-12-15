# Broker-Style Real-Time Data Architecture

This document explains the broker-style architecture implemented for distributing real-time market data to multiple clients efficiently.

## Overview

The system follows a scalable, multi-tiered architecture similar to how brokers handle market data feeds. Instead of expensive per-user API polling, we use a single WebSocket connection that efficiently distributes data to thousands of clients.

## Architecture Diagram

```
┌─────────────────────┐
│  DhanHQ WebSocket   │
│   Market Data Feed  │
└──────────┬──────────┘
           │
           │ Single Connection
           │ (up to 5,000 instruments)
           ▼
┌──────────────────────────────┐
│  WebSocket Worker            │
│  (SolidQueue Job Process)    │
│                              │
│  - Connects to DhanHQ WS    │
│  - Receives tick-by-tick     │
│  - Caches LTPs to Redis      │
│  - Publishes to Redis Pub/Sub│
└──────────┬───────────────────┘
           │
           │ Redis Pub/Sub
           │ Channel: live_ltp_updates
           ▼
┌──────────────────────────────┐
│      Redis Cache & Pub/Sub  │
│                              │
│  Cache: ltp:SEGMENT:ID      │
│  Channel: live_ltp_updates   │
└──────────┬───────────────────┘
           │
           │ Multiple Subscribers
           ├─────────────────────┬─────────────────────┐
           ▼                     ▼                     ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  Rails Instance 1│  │  Rails Instance 2│  │  Rails Instance N │
│  (Puma Server)   │  │  (Puma Server)   │  │  (Puma Server)   │
│                  │  │                  │  │                  │
│  Pub/Sub Listener│  │  Pub/Sub Listener│  │  Pub/Sub Listener│
│  → ActionCable   │  │  → ActionCable   │  │  → ActionCable   │
└────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
         │                      │                      │
         └──────────────────────┼──────────────────────┘
                               │
                               ▼
                    ┌──────────────────┐
                    │  User Browsers    │
                    │  (via ActionCable│
                    │   WebSocket)     │
                    └──────────────────┘
```

## Components

### 1. WebSocket Worker (`MarketHub::WebsocketTickStreamer`)

**Location:** `app/services/market_hub/websocket_tick_streamer.rb`

**Responsibilities:**
- Maintains single persistent connection to DhanHQ WebSocket
- Subscribes to instruments (up to 5,000 per connection)
- Receives tick-by-tick market data
- Caches LTPs to Redis: `SETEX ltp:SEGMENT:SECURITY_ID 30 <price>`
- Publishes ticks to Redis Pub/Sub: `PUBLISH live_ltp_updates <JSON>`

**Key Features:**
- Runs in SolidQueue worker process (separate from Puma)
- Automatic reconnection handled by dhanhq-client gem
- Efficient: One connection serves all users

### 2. Redis Pub/Sub Listener (`MarketHub::LtpPubSubListener`)

**Location:** `app/services/market_hub/ltp_pubsub_listener.rb`

**Responsibilities:**
- Subscribes to Redis Pub/Sub channel (`live_ltp_updates`)
- Receives tick updates from WebSocket worker
- Broadcasts updates via ActionCable to connected clients
- Runs in background thread (doesn't block Rails)

**Key Features:**
- Automatically starts on Rails boot (via initializer)
- Graceful shutdown on application exit
- Multiple Rails instances can subscribe to same channel
- Decouples WebSocket worker from Rails web servers

### 3. High-Performance API (`Api::V1::CurrentPricesController`)

**Location:** `app/controllers/api/v1/current_prices_controller.rb`

**Responsibilities:**
- Provides bulk LTP retrieval for initial page load
- Uses Redis MGET for optimal performance (single round trip)
- Falls back to REST API if cache is empty

**Usage:**
```bash
GET /api/v1/current_prices?keys=NSE_EQ:1333,NSE_EQ:11536
```

### 4. Frontend (ActionCable + JavaScript)

**Location:** `app/javascript/controllers/dashboard_controller.js`

**Responsibilities:**
- Subscribes to ActionCable `dashboard_updates` channel
- Receives real-time LTP updates
- Updates UI immediately when prices change
- Falls back to API polling if WebSocket unavailable

## Data Flow

### Real-Time Update Flow

1. **DhanHQ WebSocket** → Sends tick to WebSocket worker
2. **WebSocket Worker** → Caches LTP in Redis (`ltp:SEGMENT:SECURITY_ID`)
3. **WebSocket Worker** → Publishes to Redis Pub/Sub (`live_ltp_updates`)
4. **Redis Pub/Sub** → Distributes message to all subscribers
5. **Rails Pub/Sub Listener** → Receives message from Redis
6. **Rails Pub/Sub Listener** → Broadcasts via ActionCable (`dashboard_updates`)
7. **Browser** → Receives update via ActionCable WebSocket
8. **Browser** → Updates UI with new price

### Initial Page Load Flow

1. **Browser** → Requests page from Rails
2. **Rails** → Renders HTML with instrument keys
3. **Browser** → Calls API: `GET /api/v1/current_prices?keys=...`
4. **Rails API** → Reads from Redis cache using MGET
5. **Rails API** → Returns JSON with prices
6. **Browser** → Renders initial prices
7. **Browser** → Subscribes to ActionCable for real-time updates

## Benefits

### Cost Efficiency

| Approach                   | Cost Model                                                                                                       |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **Per-User Polling**       | One HTTP request per user per poll interval (e.g., every 5 sec). Cost scales with users × frequency.             |
| **Broker-Style (Current)** | One WebSocket connection (fixed monthly cost ~₹499) for unlimited users. Cost is fixed regardless of user count. |

### Scalability

- **Horizontal Scaling:** Add more Rails instances without additional API calls
- **Single Feed:** One WebSocket connection serves all Rails instances
- **Efficient Distribution:** Redis Pub/Sub handles message distribution

### Performance

- **Latency:** Near real-time updates (< 1 second)
- **Efficiency:** Push model (no polling overhead)
- **Bulk Reads:** Redis MGET for efficient bulk retrieval

### Reliability

- **Decoupled:** WebSocket worker independent of Rails
- **Redundancy:** Multiple Rails instances can subscribe to same feed
- **Graceful Degradation:** Falls back to polling if WebSocket unavailable

## Configuration

### Environment Variables

```bash
# Required: Enable WebSocket
export DHANHQ_WS_ENABLED=true

# Required: Redis connection
export REDIS_URL=redis://localhost:6379/0

# Optional: WebSocket mode (ticker, quote, full)
export DHANHQ_WS_MODE=quote
```

### Initialization

The Pub/Sub listener automatically starts when Rails boots (via `config/initializers/ltp_pubsub_listener.rb`). No manual action required.

### Graceful Shutdown

The listener automatically stops on application exit (registered in `at_exit` handler).

## Monitoring

### Health Check

```bash
curl http://localhost:3000/api/v1/health/market_stream
```

### Redis Keys

```bash
# Check cached LTPs
redis-cli KEYS "ltp:*"

# Monitor Pub/Sub channel
redis-cli MONITOR | grep "live_ltp_updates"
```

### Logs

The services log to Rails logger:
- WebSocket connection status
- Pub/Sub subscription status
- Tick reception and broadcasting
- Errors and warnings

## Troubleshooting

### No Updates Arriving

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
   # Check logs for: [MarketHub::LtpPubSubListener]
   tail -f log/development.log | grep LtpPubSubListener
   ```

4. **Check ActionCable:**
   - Open browser DevTools → Network → WS
   - Verify WebSocket connection to `/cable`

### Performance Issues

1. **Use Redis (not Rails.cache)** for optimal performance
2. **Monitor Redis memory** usage
3. **Check WebSocket connection** stability
4. **Verify Pub/Sub listener** is running

## Comparison: Before vs After

### Before (Polling-Based)

```
Browser 1 → Polls API every 5s → DhanHQ REST API
Browser 2 → Polls API every 5s → DhanHQ REST API
Browser 3 → Polls API every 5s → DhanHQ REST API
...
Browser N → Polls API every 5s → DhanHQ REST API

Cost: N users × (1 request / 5s) = High API usage
Latency: 5 seconds (polling interval)
Scalability: Limited by API rate limits
```

### After (Broker-Style)

```
DhanHQ WebSocket → WebSocket Worker → Redis Pub/Sub
                                          │
                                          ├─→ Rails Instance 1 → ActionCable → Browser 1
                                          ├─→ Rails Instance 2 → ActionCable → Browser 2
                                          └─→ Rails Instance N → ActionCable → Browser N

Cost: 1 WebSocket connection (fixed monthly cost)
Latency: < 1 second (real-time push)
Scalability: Unlimited (horizontal scaling)
```

## References

- [Real-Time LTP Streaming Documentation](./REAL_TIME_LTP_STREAMING.md)
- [Market Data LTP Access Guide](./MARKET_DATA_LTP_ACCESS.md)
- [WebSocket Thread Architecture](./WEBSOCKET_THREAD_ARCHITECTURE.md)
