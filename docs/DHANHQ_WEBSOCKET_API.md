# DhanHQ WebSocket API Implementation Guide

## Overview

This document describes how to implement WebSocket-based real-time tick streaming using the `dhanhq-client` gem.

**Gem Repository**: https://github.com/shubhamtaywade82/dhanhq-client

## Current Implementation Status

The `WebsocketTickStreamer` service has been implemented with multiple API fallbacks to handle different possible WebSocket API structures from the gem. However, **the actual WebSocket API structure needs to be verified** by checking the gem's documentation or source code.

## Possible WebSocket API Structures

Based on common Ruby gem patterns and the gem's structure, the WebSocket API might be:

### Option 1: `DhanHQ::WebSocket::MarketFeed`
```ruby
client = DhanHQ::WebSocket::MarketFeed.new(
  on_tick: ->(tick) { handle_tick(tick) },
  on_error: ->(error) { handle_error(error) },
  on_close: -> { handle_close }
)
client.subscribe([{ ExchangeSegment: "NSE_EQ", SecurityId: "11536" }])
```

### Option 2: `DhanHQ::WebSocket::Client`
```ruby
client = DhanHQ::WebSocket::Client.new(
  type: :market_feed,
  on_tick: ->(tick) { handle_tick(tick) },
  on_error: ->(error) { handle_error(error) },
  on_close: -> { handle_close }
)
client.subscribe([{ ExchangeSegment: "NSE_EQ", SecurityId: "11536" }])
```

### Option 3: `DhanHQ::Client` with websocket method
```ruby
client = DhanHQ::Client.new(api_type: :data_api)
ws_client = client.market_feed_websocket(
  on_tick: ->(tick) { handle_tick(tick) },
  on_error: ->(error) { handle_error(error) },
  on_close: -> { handle_close }
)
ws_client.subscribe([{ ExchangeSegment: "NSE_EQ", SecurityId: "11536" }])
```

## Verification Steps

To verify the actual WebSocket API:

1. **Check Gem Documentation**:
   ```bash
   # View gem README
   bundle show DhanHQ
   cat $(bundle show DhanHQ)/README.md
   ```

2. **Inspect Gem Source**:
   ```bash
   # Check WebSocket classes
   bundle exec rails runner "require 'dhan_hq'; puts DhanHQ.constants"
   bundle exec rails runner "require 'dhan_hq'; puts DhanHQ::WebSocket.constants rescue puts 'No WebSocket module'"
   ```

3. **Check Gem Examples**:
   - Look for examples in the gem's `examples/` directory
   - Check the gem's test files for usage examples

4. **Test WebSocket Connection**:
   ```ruby
   # In Rails console
   require 'dhan_hq'
   
   # Try different API structures
   begin
     ws = DhanHQ::WebSocket::MarketFeed.new
     puts "Found: DhanHQ::WebSocket::MarketFeed"
   rescue => e
     puts "Not found: #{e.message}"
   end
   ```

## Current Implementation

The `WebsocketTickStreamer` service (`app/services/market_hub/websocket_tick_streamer.rb`) includes:

1. **Multiple API fallbacks** - Tries different possible API structures
2. **Flexible tick handling** - Handles various tick data formats
3. **Error handling** - Graceful fallback if WebSocket is not available
4. **ActionCable integration** - Broadcasts ticks to connected clients

## Next Steps

1. **Verify API Structure**: Check the actual gem API and update the implementation
2. **Test Connection**: Test WebSocket connection with real DhanHQ credentials
3. **Handle Reconnection**: Implement robust reconnection logic
4. **Rate Limiting**: Handle WebSocket rate limits if any

## References

- Gem Repository: https://github.com/shubhamtaywade82/dhanhq-client
- DhanHQ API Documentation: https://dhanhq.co/api-docs/
- WebSocket Implementation: `app/services/market_hub/websocket_tick_streamer.rb`
