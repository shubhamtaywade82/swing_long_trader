# DhanHQ WebSocket API Implementation Guide

## Overview

This document describes the WebSocket-based real-time tick streaming implementation using the `dhanhq-client` gem.

**Gem Repository**: https://github.com/shubhamtaywade82/dhanhq-client

## WebSocket API (Verified)

Based on the dhanhq-client gem documentation, the WebSocket API is:

### Client Initialization

```ruby
# Modes: :ticker (LTP+LTT), :quote (OHLCV+totals, recommended), :full (quote+OI+depth)
ws = DhanHQ::WS::Client.new(mode: :quote).start
```

### Event Handlers

```ruby
ws.on(:tick) do |t|
  puts "[#{t[:segment]}:#{t[:security_id]}] LTP=#{t[:ltp]} kind=#{t[:kind]}"
end
```

### Subscription

```ruby
# Subscribe instruments (≤100 per frame; client auto-chunks)
ws.subscribe_one(segment: "NSE_EQ", security_id: "12345")
ws.subscribe_one(segment: "IDX_I", security_id: "13")  # NIFTY index
```

### Unsubscription

```ruby
ws.unsubscribe_one(segment: "NSE_EQ", security_id: "12345")
```

### Disconnect

```ruby
# Graceful disconnect (sends broker disconnect code 12, no reconnect)
ws.disconnect!

# Or hard stop (no broker message, just closes and halts loop)
ws.stop

# Safety: kill all local sockets (useful in IRB)
DhanHQ::WS.disconnect_all_local!
```

## Tick Format

Normalized ticks are Hash objects:

```ruby
{
  kind: :quote,                 # :ticker | :quote | :full | :oi | :prev_close | :misc
  segment: "NSE_FNO",           # string enum
  security_id: "12345",
  ltp: 101.5,
  ts:  1723791300,              # LTT epoch (sec) if present
  vol: 123456,                  # quote/full
  atp: 100.9,                   # quote/full
  day_open: 100.1, day_high: 102.4, day_low: 99.5, day_close: nil,
  oi: 987654,                   # full or OI packet
  bid: 101.45, ask: 101.55      # from depth (mode :full)
}
```

## Exchange Segment Enums

| Enum | Exchange | Segment |
|------|----------|---------|
| IDX_I | Index | Index Value |
| NSE_EQ | NSE | Equity Cash |
| NSE_FNO | NSE | Futures & Options |
| NSE_CURRENCY | NSE | Currency |
| BSE_EQ | BSE | Equity Cash |
| MCX_COMM | MCX | Commodity |
| BSE_CURRENCY | BSE | Currency |
| BSE_FNO | BSE | Futures & Options |

## Implementation

The `WebsocketTickStreamer` service (`app/services/market_hub/websocket_tick_streamer.rb`) implements:

1. **Client initialization** with configurable mode (`:quote` default)
2. **Tick handler** that broadcasts via ActionCable
3. **Subscription management** for screener instruments
4. **Automatic reconnection** (handled by gem with exponential backoff)
5. **Graceful shutdown** using `disconnect!`

## Features

- **Automatic reconnection**: Gem handles reconnection with exponential backoff
- **Subscription persistence**: On reconnect, client resends subscription snapshot (idempotent)
- **Rate limiting**: Handles 429 errors with 60s cool-off
- **Connection limits**: Up to 5 WS connections per user (per Dhan)
- **Batch subscriptions**: Up to 100 instruments per SUB message (auto-chunked)

## Configuration

Set environment variables:

```bash
# Enable WebSocket
export DHANHQ_WS_ENABLED=true

# Set mode (:ticker, :quote, :full)
export DHANHQ_WS_MODE=quote  # default: quote

# Log level
export DHAN_LOG_LEVEL=INFO
```

## Usage Example

```ruby
# In Rails initializer or service
ws = DhanHQ::WS::Client.new(mode: :quote).start

ws.on(:tick) do |tick|
  # Broadcast to ActionCable
  ActionCable.server.broadcast("dashboard_updates", {
    type: "screener_ltp_update",
    symbol: find_symbol(tick[:segment], tick[:security_id]),
    ltp: tick[:ltp],
    timestamp: Time.current.iso8601
  })
end

# Subscribe to screener stocks
screener_instruments.each do |instrument|
  ws.subscribe_one(
    segment: instrument.exchange_segment,
    security_id: instrument.security_id.to_s
  )
end
```

## References

- Gem Repository: https://github.com/shubhamtaywade82/dhanhq-client
- Implementation: `app/services/market_hub/websocket_tick_streamer.rb`
- Job: `app/jobs/market_hub/websocket_tick_streamer_job.rb`
