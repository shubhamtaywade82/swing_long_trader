# Market Data LTP Access Guide

This guide explains how other services can access cached LTPs (Last Traded Prices) from the WebSocket streaming service.

## Overview

LTPs are cached in Redis by the `MarketHub::WebsocketTickStreamer` service with key format: `ltp:SEGMENT:SECURITY_ID` (e.g., `ltp:NSE_EQ:1333`). The `MarketData::LtpCache` service provides a clean interface to access these cached prices.

## Basic Usage

### Direct Service Access

```ruby
# Get single LTP
price = MarketData::LtpCache.get("NSE_EQ", "1333")
# => 1234.56 or nil if not cached

# Get multiple LTPs (efficient - uses Redis MGET)
prices = MarketData::LtpCache.get_multiple([
  ["NSE_EQ", "1333"],
  ["NSE_EQ", "11536"]
])
# => { "NSE_EQ:1333" => 1234.56, "NSE_EQ:11536" => 5678.90 }
```

### Using Instrument Model

The `Instrument` model includes `MarketData::LtpAccessor` concern, so you can access LTPs directly:

```ruby
instrument = Instrument.find(1)

# Get current LTP
ltp = instrument.current_ltp
# => 1234.56 or nil if not cached

# Check if LTP is cached
if instrument.ltp_cached?
  ltp = instrument.current_ltp
  # Use LTP...
end

# Get LTPs for multiple instruments
instruments = Instrument.where(id: [1, 2, 3])
prices = MarketData::LtpCache.get_by_instruments(instruments)
# => { 1 => 1234.56, 2 => 5678.90, 3 => nil }
```

## Usage in Services

### Example: Order Placement Service

```ruby
class Orders::PlaceOrderService
  def initialize(instrument:, quantity:, order_type:)
    @instrument = instrument
    @quantity = quantity
    @order_type = order_type
  end

  def call
    # Get current LTP for price validation
    current_ltp = @instrument.current_ltp

    if current_ltp.nil?
      return { success: false, error: "LTP not available for #{@instrument.symbol_name}" }
    end

    # Use LTP for order placement logic
    if @order_type == "MARKET"
      order_price = current_ltp
    elsif @order_type == "LIMIT"
      # Use limit price from params
      order_price = params[:limit_price]
    end

    # Place order...
    { success: true, order_price: order_price, current_ltp: current_ltp }
  end
end
```

### Example: Portfolio Valuation Service

```ruby
class Portfolios::ValuationService
  def initialize(positions:)
    @positions = positions
  end

  def call
    # Get all instruments
    instruments = @positions.map(&:instrument).compact.uniq

    # Get all LTPs in one call (efficient)
    ltps = MarketData::LtpCache.get_by_instruments(instruments)

    # Calculate portfolio value
    total_value = @positions.sum do |position|
      ltp = ltps[position.instrument_id]
      next 0 unless ltp

      position.quantity * ltp
    end

    { total_value: total_value, positions_count: @positions.size }
  end
end
```

### Example: Price Alert Service

```ruby
class Alerts::PriceAlertService
  include MarketData::LtpAccessor

  def initialize(instrument:, target_price:, direction:)
    @instrument = instrument
    @target_price = target_price
    @direction = direction # :above or :below
  end

  def check_alert
    current_ltp = @instrument.current_ltp
    return false unless current_ltp

    case @direction
    when :above
      current_ltp >= @target_price
    when :below
      current_ltp <= @target_price
    else
      false
    end
  end
end
```

## API Reference

### MarketData::LtpCache

#### `get(segment, security_id)`
Get LTP for a single instrument.

**Parameters:**
- `segment` (String): Exchange segment (e.g., "NSE_EQ")
- `security_id` (String, Integer): Security ID (e.g., "1333")

**Returns:** `Float` or `nil`

**Example:**
```ruby
price = MarketData::LtpCache.get("NSE_EQ", "1333")
```

#### `get_multiple(instruments)`
Get multiple LTPs efficiently using Redis MGET.

**Parameters:**
- `instruments` (Array): Array of `[segment, security_id]` pairs

**Returns:** `Hash<String, Float>` with keys like `"NSE_EQ:1333" => 1234.56`

**Example:**
```ruby
prices = MarketData::LtpCache.get_multiple([
  ["NSE_EQ", "1333"],
  ["NSE_EQ", "11536"]
])
```

#### `get_by_instrument(instrument)`
Get LTP by Instrument model.

**Parameters:**
- `instrument` (Instrument): Instrument model instance

**Returns:** `Float` or `nil`

**Example:**
```ruby
instrument = Instrument.find(1)
price = MarketData::LtpCache.get_by_instrument(instrument)
```

#### `get_by_instruments(instruments)`
Get LTPs for multiple Instrument models.

**Parameters:**
- `instruments` (ActiveRecord::Relation, Array): Collection of instruments

**Returns:** `Hash<Integer, Float>` with `instrument_id => LTP value`

**Example:**
```ruby
instruments = Instrument.where(id: [1, 2, 3])
prices = MarketData::LtpCache.get_by_instruments(instruments)
# => { 1 => 1234.56, 2 => 5678.90, 3 => nil }
```

#### `cached?(segment, security_id)`
Check if LTP is cached.

**Parameters:**
- `segment` (String): Exchange segment
- `security_id` (String, Integer): Security ID

**Returns:** `Boolean`

**Example:**
```ruby
MarketData::LtpCache.cached?("NSE_EQ", "1333")
# => true or false
```

#### `get_all(pattern: nil)`
Get all cached LTPs (use with caution - can be slow).

**Parameters:**
- `pattern` (String, optional): Redis key pattern (default: "ltp:*")

**Returns:** `Hash<String, Float>`

**Example:**
```ruby
all_ltps = MarketData::LtpCache.get_all
```

#### `stats`
Get cache statistics.

**Returns:** `Hash` with statistics

**Example:**
```ruby
MarketData::LtpCache.stats
# => { total_cached: 150, cache_prefix: "ltp", redis_available: true }
```

### MarketData::LtpAccessor Concern

When included in a model or service, provides these instance methods:

#### `current_ltp`
Get current LTP for this model instance (if it responds to `exchange_segment` and `security_id`).

**Returns:** `Float` or `nil`

#### `current_ltp_for(segment, security_id)`
Get current LTP for a segment and security_id.

**Parameters:**
- `segment` (String): Exchange segment
- `security_id` (String, Integer): Security ID

**Returns:** `Float` or `nil`

#### `current_ltps_for(instruments)`
Get multiple LTPs efficiently.

**Parameters:**
- `instruments` (Array): Array of `[segment, security_id]` pairs

**Returns:** `Hash<String, Float>`

#### `ltp_cached?`
Check if LTP is cached for this model instance.

**Returns:** `Boolean`

## Performance Considerations

1. **Use `get_multiple` or `get_by_instruments`** for bulk operations - they use Redis MGET for efficiency
2. **LTPs expire after 30 seconds** if not updated - always check for `nil` values
3. **Redis is recommended** for optimal performance - falls back to Rails.cache if Redis unavailable
4. **Cache is only populated during market hours** when WebSocket service is running

## Error Handling

Always handle `nil` values gracefully:

```ruby
ltp = instrument.current_ltp

if ltp.nil?
  # Fallback: fetch from API or use last known price
  ltp = fetch_ltp_from_api(instrument)
end

# Use LTP...
```

## Integration Examples

### Include in Custom Services

```ruby
class MyCustomService
  include MarketData::LtpAccessor

  def call
    # Now you can use current_ltp_for, etc.
    ltp = current_ltp_for("NSE_EQ", "1333")
    # ...
  end
end
```

### Include in Models

```ruby
class Position < ApplicationRecord
  include MarketData::LtpAccessor

  def current_value
    ltp = current_ltp_for(instrument.exchange_segment, instrument.security_id)
    return 0 unless ltp

    quantity * ltp
  end
end
```

## Monitoring

Check cache statistics:

```ruby
stats = MarketData::LtpCache.stats
# => { total_cached: 150, cache_prefix: "ltp", redis_available: true }
```

## Notes

- LTPs are cached with 30-second TTL
- Cache is only populated when WebSocket service is running (during market hours)
- Always check for `nil` values before using LTPs
- Use bulk methods (`get_multiple`, `get_by_instruments`) for better performance
