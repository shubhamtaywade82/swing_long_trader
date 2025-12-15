# Real-Time LTP Streaming Implementation

This document describes the implementation of the real-time Last Traded Price (LTP) streaming system using WebSocket, Redis, and a high-performance API.

## Architecture Overview

The system consists of three main components:

1. **WebSocket Streaming Service** (`MarketData::StreamingService`)
   - Runs as a standalone process (separate from Puma)
   - Connects to DhanHQ WebSocket API
   - Subscribes to instruments from active screener
   - Streams LTPs into Redis cache

2. **High-Performance Read API** (`Api::V1::CurrentPricesController`)
   - Fast endpoint: `GET /api/v1/current_prices?keys=NSE_EQ:1333,NSE_EQ:11536`
   - Uses Redis MGET for bulk retrieval (single round trip)
   - Returns JSON with prices hash

3. **Frontend Polling** (JavaScript in screener views)
   - Polls API every 1.5 seconds
   - Updates DOM elements with new prices
   - Visual feedback for price changes (flash animation)

## Components

### 1. Streaming Service

**File:** `app/services/market_data/streaming_service.rb`

- Connects to DhanHQ WebSocket using `DhanHQ::WS::Client`
- Subscribes to instruments from latest screener results
- Caches LTPs in Redis with key format: `ltp:SEGMENT:SECURITY_ID`
- Refreshes subscription list every 5 minutes
- Sends heartbeat every 30 seconds

**Usage:**
```ruby
service = MarketData::StreamingService.new
service.start  # Blocks until market closes or stopped
```

### 2. API Endpoint

**File:** `app/controllers/api/v1/current_prices_controller.rb`

**Route:** `GET /api/v1/current_prices?keys=NSE_EQ:1333,NSE_EQ:11536`

**Response:**
```json
{
  "prices": {
    "NSE_EQ:1333": 1234.56,
    "NSE_EQ:11536": 5678.90
  },
  "timestamp": "2024-01-01T12:00:00Z",
  "count": 2,
  "cached_count": 2
}
```

### 3. Frontend Integration

**Files:**
- `app/views/screeners/swing.html.erb`
- `app/views/screeners/longterm.html.erb`
- `app/views/screeners/_screener_table.html.erb`
- `app/views/screeners/_longterm_screener_table.html.erb`

**Features:**
- Automatically starts polling when page loads
- Collects all `data-instrument-key` attributes from table rows
- Polls API every 1.5 seconds
- Updates price cells with visual feedback (flash animation)
- Handles price direction (up/down) with color coding

## Setup & Deployment

### 1. Install Dependencies

Add Redis gem to Gemfile (already added):
```ruby
gem "redis", "~> 5.0", require: false
```

Run:
```bash
bundle install
```

### 2. Configure Redis (Optional but Recommended)

Set `REDIS_URL` environment variable:
```bash
export REDIS_URL=redis://localhost:6379/0
```

**Note:** The system falls back to `Rails.cache` if Redis is not available, but Redis is recommended for optimal MGET performance.

### 3. Enable WebSocket

Set environment variable:
```bash
export DHANHQ_WS_ENABLED=true
```

### 4. Start the Streaming Service

**Development (Foreman):**
The `Procfile` includes:
```
market_stream: bundle exec rake market:start_stream
```

Start with:
```bash
foreman start
```

**Production (Systemd/Supervisor):**
Create a systemd service or supervisor config to run:
```bash
bundle exec rake market:start_stream
```

**Manual Start:**
```bash
bundle exec rake market:start_stream
```

### 5. Verify Service is Running

Check health endpoint:
```bash
curl http://localhost:3000/api/v1/health/market_stream
```

Expected response:
```json
{
  "status": "healthy",
  "heartbeat_age_seconds": 15.2,
  "heartbeat_timestamp": "2024-01-01T12:00:00Z",
  "timestamp": "2024-01-01T12:00:15Z"
}
```

## Usage

### Starting the Service

The service automatically:
1. Loads instruments from latest screener results
2. Connects to DhanHQ WebSocket
3. Subscribes to all instruments
4. Caches LTPs in Redis as they arrive
5. Refreshes subscription list every 5 minutes

### Frontend

The screener views automatically:
1. Collect instrument keys from table rows
2. Poll `/api/v1/current_prices` every 1.5 seconds
3. Update price cells with visual feedback
4. Show price direction (green for up, red for down)

### Manual API Usage

```bash
# Get prices for multiple instruments
curl "http://localhost:3000/api/v1/current_prices?keys=NSE_EQ:1333,NSE_EQ:11536"

# Response
{
  "prices": {
    "NSE_EQ:1333": 1234.56,
    "NSE_EQ:11536": 5678.90
  },
  "timestamp": "2024-01-01T12:00:00Z",
  "count": 2,
  "cached_count": 2
}
```

## Configuration

### Environment Variables

- `DHANHQ_WS_ENABLED=true` - Enable WebSocket (required)
- `DHANHQ_WS_MODE=quote` - WebSocket mode: `ticker`, `quote`, or `full` (default: `quote`)
- `REDIS_URL=redis://localhost:6379/0` - Redis connection URL (optional, falls back to Rails.cache)

### Service Configuration

**File:** `app/services/market_data/streaming_service.rb`

- `LTP_CACHE_TTL = 30.seconds` - LTP cache expiration
- `SUBSCRIPTION_REFRESH_INTERVAL = 5.minutes` - How often to refresh instrument list
- `HEARTBEAT_INTERVAL = 30.seconds` - Heartbeat frequency

### Frontend Configuration

**Files:** `app/views/screeners/*.html.erb`

- Poll interval: 1500ms (1.5 seconds)
- Visual feedback duration: 500ms
- Price cell selector: `.js-ltp-cell[data-instrument-key]`

## Monitoring

### Health Check

Endpoint: `GET /api/v1/health/market_stream`

Returns:
- `status`: `healthy`, `stale`, `not_running`, or `error`
- `heartbeat_age_seconds`: Age of last heartbeat
- `heartbeat_timestamp`: ISO8601 timestamp of heartbeat

### Logs

The streaming service logs to Rails logger:
- Connection status
- Subscription counts
- Tick reception (debug level)
- Errors and warnings

### Redis Keys

- `ltp:SEGMENT:SECURITY_ID` - LTP cache (TTL: 30 seconds)
- `market_stream:heartbeat` - Service heartbeat (TTL: 60 seconds)

## Troubleshooting

### Service Not Starting

1. Check WebSocket is enabled: `DHANHQ_WS_ENABLED=true`
2. Check DhanHQ credentials are set: `DHANHQ_CLIENT_ID`, `DHANHQ_ACCESS_TOKEN`
3. Check logs: `tail -f log/development.log`

### No Prices Updating

1. Verify service is running: `curl /api/v1/health/market_stream`
2. Check Redis has data: `redis-cli KEYS "ltp:*"`
3. Check browser console for JavaScript errors
4. Verify instrument keys are present in HTML: `data-instrument-key` attributes

### Performance Issues

1. Use Redis (not Rails.cache) for optimal MGET performance
2. Reduce poll interval if needed (default: 1500ms)
3. Monitor Redis memory usage
4. Check WebSocket connection stability

## Future Enhancements

- [ ] WebSocket reconnection with exponential backoff
- [ ] Subscription management UI
- [ ] Price change notifications/alerts
- [ ] Historical price tracking
- [ ] Multi-timeframe price aggregation
- [ ] Rate limiting for API endpoint
