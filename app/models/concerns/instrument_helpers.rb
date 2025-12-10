# frozen_string_literal: true

require 'bigdecimal'
require 'date'

module InstrumentHelpers
  extend ActiveSupport::Concern
  include CandleExtension

  included do
    enum :exchange, { nse: 'NSE', bse: 'BSE', mcx: 'MCX' }
    enum :segment, { index: 'I', equity: 'E', currency: 'C', derivatives: 'D', commodity: 'M' }, prefix: true
    enum :instrument_code, {
      index: 'INDEX',
      futures_index: 'FUTIDX',
      options_index: 'OPTIDX',
      equity: 'EQUITY',
      futures_stock: 'FUTSTK',
      options_stock: 'OPTSTK',
      futures_currency: 'FUTCUR',
      options_currency: 'OPTCUR',
      futures_commodity: 'FUTCOM',
      options_commodity: 'OPTFUT'
    }, prefix: true

    scope :nse, -> { where(exchange: 'NSE') }
    scope :bse, -> { where(exchange: 'BSE') }

    # Removed WebSocket subscribe/unsubscribe methods - swing trading uses REST API only
  end

  # Simplified LTP fetching - uses REST API only (no WebSocket)
  def ltp
    fetch_ltp_from_api
  rescue StandardError => e
    # Suppress 429 rate limit errors (expected during high load)
    error_msg = e.message.to_s
    is_rate_limit = error_msg.include?('429') || error_msg.include?('rate limit') || error_msg.include?('Rate limit')
    Rails.logger.error("Failed to fetch LTP for #{self.class.name} #{security_id}: #{error_msg}") unless is_rate_limit
    nil
  end

  def latest_ltp
    price = quote_ltp || fetch_ltp_from_api
    price.present? ? BigDecimal(price.to_s) : nil
  end

  # Resolves an actionable LTP for downstream order placement.
  # Simplified for swing trading - uses REST API only
  # Priority order:
  # 1. `meta[:ltp]` if provided
  # 2. REST API via DhanHQ
  #
  # @param segment [String]
  # @param security_id [String, Integer]
  # @param meta [Hash]
  # @param fallback_to_api [Boolean] Whether to fallback to REST API (always true for swing trading)
  # @return [BigDecimal, nil]
  def resolve_ltp(segment:, security_id:, meta: {}, fallback_to_api: true)
    ltp_from_meta = meta&.dig(:ltp)
    return BigDecimal(ltp_from_meta.to_s) if ltp_from_meta.present?

    # Use REST API (swing trading doesn't use WebSocket)
    if fallback_to_api
      api_ltp = fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
      return BigDecimal(api_ltp.to_s) if api_ltp.present?
    end

    nil
  rescue StandardError => e
    Rails.logger.error("Failed to resolve LTP for #{segment}:#{security_id} - #{e.message}")
    nil
  end

  # Fetches LTP from REST API for a specific segment and security_id
  # Simplified for swing trading - uses REST API only (no WebSocket)
  # @param segment [String] Exchange segment (e.g., "IDX_I", "NSE_EQ")
  # @param security_id [String, Integer] Security ID
  # @param subscribe [Boolean] Ignored for swing trading (kept for API compatibility)
  # @return [Numeric, nil]
  def fetch_ltp_from_api_for_segment(segment:, security_id:, subscribe: false)
    # Use REST API only (swing trading doesn't use WebSocket)
    segment_enum = segment.to_s.upcase
    payload = { segment_enum => [security_id.to_i] }
    response = DhanHQ::Models::MarketFeed.ltp(payload)

    return nil unless response.is_a?(Hash) && response['status'] == 'success'

    data = response.dig('data', segment_enum, security_id.to_s)
    data&.dig('last_price')
  rescue StandardError => e
    # Suppress 429 rate limit errors (expected during high load)
    error_msg = e.message.to_s
    is_rate_limit = error_msg.include?('429') || error_msg.include?('rate limit') || error_msg.include?('Rate limit')
    unless is_rate_limit
      Rails.logger.error("Failed to fetch LTP from API for #{self.class.name} #{security_id}: #{error_msg}")
    end
    nil
  end

  # Generates a short, gateway-safe client order identifier.
  # @param side [Symbol, String]
  # @param security_id [String]
  # @return [String]
  def default_client_order_id(side:, security_id:)
    ts = Time.current.to_i.to_s[-6..]
    "AS-#{side.to_s.upcase[0..2]}-#{security_id}-#{ts}"
  end

  # Removed scalper-specific methods:
  # - ensure_ws_subscription! (WebSocket subscription)
  # - after_order_track! (PositionTracker creation)
  # These will be replaced with swing trading-specific position tracking if needed

  def quote_ltp
    return unless respond_to?(:quotes)

    quote = quotes.order(tick_time: :desc).first
    quote&.ltp&.to_f
  rescue StandardError => e
    Rails.logger.error("Failed to fetch latest quote LTP for #{self.class.name} #{security_id}: #{e.message}")
    nil
  end

  # Simplified for swing trading - uses REST API only
  def fetch_ltp_from_api
    response = DhanHQ::Models::MarketFeed.ltp(exch_segment_enum)
    response.dig('data', exchange_segment, security_id.to_s, 'last_price') if response['status'] == 'success'
  rescue StandardError => e
    # Suppress 429 rate limit errors (expected during high load)
    error_msg = e.message.to_s
    is_rate_limit = error_msg.include?('429') || error_msg.include?('rate limit') || error_msg.include?('Rate limit')
    unless is_rate_limit
      error_info = Concerns::DhanhqErrorHandler.handle_dhanhq_error(
        e,
        context: "fetch_ltp_from_api(#{self.class.name} #{security_id})"
      )
      Rails.logger.error("Failed to fetch LTP from API for #{self.class.name} #{security_id}: #{error_msg}")
    end
    nil
  end

  def subscribe_params
    { ExchangeSegment: exchange_segment, SecurityId: security_id.to_s }
  end

  # Removed WebSocket methods:
  # - ws_get (Live::TickCache access)
  # - ws_ltp (WebSocket LTP)
  # Swing trading uses REST API only

  def ohlc
    response = DhanHQ::Models::MarketFeed.ohlc(exch_segment_enum)
    response['status'] == 'success' ? response.dig('data', exchange_segment, security_id.to_s) : nil
  rescue StandardError => e
    error_info = Concerns::DhanhqErrorHandler.handle_dhanhq_error(
      e,
      context: "ohlc(#{self.class.name} #{security_id})"
    )
    Rails.logger.error("Failed to fetch OHLC for #{self.class.name} #{security_id}: #{e.message}")
    nil
  end

  def historical_ohlc(from_date: nil, to_date: nil, oi: false)
    DhanHQ::Models::HistoricalData.daily(
      securityId: security_id,
      exchangeSegment: exchange_segment,
      instrument: instrument_type || resolve_instrument_code,
      oi: oi,
      fromDate: from_date || (Time.zone.today - 365).to_s,
      toDate: to_date || (Time.zone.today - 1).to_s,
      expiryCode: 0
    )
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Historical OHLC for #{self.class.name} #{security_id}: #{e.message}")
    nil
  end

  def intraday_ohlc(interval: '5', oi: false, from_date: nil, to_date: nil, days: 2)
    to_date ||= if defined?(MarketCalendar) && MarketCalendar.respond_to?(:today_or_last_trading_day)
                   MarketCalendar.today_or_last_trading_day.to_s
                 else
                   (Time.zone.today - 1).to_s
                 end
    from_date ||= (Date.parse(to_date) - days).to_s

    instrument_code = resolve_instrument_code
    DhanHQ::Models::HistoricalData.intraday(
      security_id: security_id,
      exchange_segment: exchange_segment,
      instrument: instrument_code,
      interval: interval,
      oi: oi,
      from_date: from_date || (Time.zone.today - days).to_s,
      to_date: to_date || (Time.zone.today - 1).to_s
    )
  rescue StandardError => e
    error_info = Concerns::DhanhqErrorHandler.handle_dhanhq_error(
      e,
      context: "intraday_ohlc(#{self.class.name} #{security_id})"
    )
    Rails.logger.error("Failed to fetch Intraday OHLC for #{self.class.name} #{security_id}: #{e.message}")
    nil
  end

  def exchange_segment
    return self[:exchange_segment] if self[:exchange_segment].present?

    case [exchange&.to_sym, segment&.to_sym]
    when %i[nse index], %i[bse index]
      'IDX_I'
    when %i[nse equity]
      'NSE_EQ'
    when %i[bse equity]
      'BSE_EQ'
    when %i[nse derivatives]
      'NSE_FNO'
    when %i[bse derivatives]
      'BSE_FNO'
    when %i[nse currency]
      'NSE_CURRENCY'
    when %i[bse currency]
      'BSE_CURRENCY'
    when %i[mcx commodity]
      'MCX_COMM'
    else
      raise "Unsupported exchange and segment combination: #{exchange}, #{segment}"
    end
  end

  private

  def resolve_instrument_code
    code = instrument_code.presence || instrument_type.presence
    code ||= InstrumentTypeMapping.underlying_for(self[:instrument_code]).presence if respond_to?(:instrument_code)

    segment_value = respond_to?(:segment) ? segment.to_s.downcase : nil
    code ||= 'EQUITY' if segment_value == 'equity'
    code ||= 'INDEX' if segment_value == 'index'

    raise "Missing instrument code for #{symbol_name || security_id}" if code.blank?

    code.to_s.upcase
  end

  def depth
    response = DhanHQ::Models::MarketFeed.quote(exch_segment_enum)
    response['status'] == 'success' ? response.dig('data', exchange_segment, security_id.to_s) : nil
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Depth for #{self.class.name} #{security_id}: #{e.message}")
    nil
  end

  def exch_segment_enum
    { exchange_segment => [security_id.to_i] }
  end

  def numeric_value?(value)
    value.is_a?(Numeric) || value.to_s.match?(/\A-?\d+(\.\d+)?\z/)
  end
end
