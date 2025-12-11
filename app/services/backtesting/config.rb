# frozen_string_literal: true

module Backtesting
  # Configuration for backtesting runs
  class Config
    DEFAULT_INITIAL_CAPITAL = 100_000.0
    DEFAULT_RISK_PER_TRADE = 2.0 # 2% of capital per trade
    DEFAULT_COMMISSION_RATE = 0.0 # 0% commission (can be overridden)
    DEFAULT_SLIPPAGE_PCT = 0.0 # 0% slippage (can be overridden)

    attr_reader :initial_capital, :risk_per_trade, :commission_rate, :slippage_pct,
                :position_sizing_method, :date_range, :instrument_universe, :strategy_overrides

    def initialize(options = {})
      @initial_capital = (options[:initial_capital] || DEFAULT_INITIAL_CAPITAL).to_f
      @risk_per_trade = (options[:risk_per_trade] || DEFAULT_RISK_PER_TRADE).to_f
      @commission_rate = (options[:commission_rate] || DEFAULT_COMMISSION_RATE).to_f
      @slippage_pct = (options[:slippage_pct] || DEFAULT_SLIPPAGE_PCT).to_f
      @position_sizing_method = options[:position_sizing_method] || :risk_based
      @date_range = options[:date_range] || {}
      @instrument_universe = options[:instrument_universe] || []
      @strategy_overrides = options[:strategy_overrides] || {}
    end

    def self.from_hash(hash)
      new(
        initial_capital: hash[:initial_capital],
        risk_per_trade: hash[:risk_per_trade],
        commission_rate: hash[:commission_rate],
        slippage_pct: hash[:slippage_pct],
        position_sizing_method: hash[:position_sizing_method],
        date_range: hash[:date_range],
        instrument_universe: hash[:instrument_universe],
        strategy_overrides: hash[:strategy_overrides]
      )
    end

    def to_hash
      {
        initial_capital: @initial_capital,
        risk_per_trade: @risk_per_trade,
        commission_rate: @commission_rate,
        slippage_pct: @slippage_pct,
        position_sizing_method: @position_sizing_method,
        date_range: @date_range,
        instrument_universe: @instrument_universe,
        strategy_overrides: @strategy_overrides
      }
    end

    def from_date
      @date_range[:from_date] || Date.today - 1.year
    end

    def to_date
      @date_range[:to_date] || Date.today
    end

    def risk_amount_per_trade
      (@initial_capital * @risk_per_trade / 100.0).round(2)
    end

    def apply_slippage(price, direction)
      return price if @slippage_pct.zero?

      slippage = price * @slippage_pct / 100.0
      case direction
      when :long
        price + slippage # Buy at higher price
      when :short
        price - slippage # Sell at lower price
      else
        price
      end
    end

    def apply_commission(amount)
      return amount if @commission_rate.zero?

      amount * (1 + @commission_rate / 100.0)
    end

    def validate!
      errors = []

      errors << 'Initial capital must be positive' if @initial_capital <= 0
      errors << 'Risk per trade must be between 0.1 and 10%' if @risk_per_trade < 0.1 || @risk_per_trade > 10
      errors << 'Commission rate must be non-negative' if @commission_rate < 0
      errors << 'Slippage must be non-negative' if @slippage_pct < 0
      errors << 'Invalid position sizing method' unless %i[risk_based fixed equal_weight].include?(@position_sizing_method)
      errors << 'Invalid date range' if from_date >= to_date

      raise ArgumentError, errors.join(', ') if errors.any?

      true
    end
  end
end

