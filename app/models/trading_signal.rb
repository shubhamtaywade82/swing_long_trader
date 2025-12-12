# frozen_string_literal: true

class TradingSignal < ApplicationRecord
  belongs_to :instrument
  belongs_to :order, optional: true
  belongs_to :paper_position, optional: true

  validates :symbol, :direction, :entry_price, :quantity, :order_value, :signal_generated_at, presence: true
  validates :direction, inclusion: { in: %w[long short] }
  validates :execution_type, inclusion: { in: %w[paper live none] }, allow_nil: true
  validates :execution_status, inclusion: { in: %w[executed not_executed pending_approval failed] }, allow_nil: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :order_value, numericality: { greater_than: 0 }

  scope :executed, -> { where(executed: true) }
  scope :not_executed, -> { where(executed: false) }
  scope :pending_approval, -> { where(execution_status: "pending_approval") }
  scope :failed, -> { where(execution_status: "failed") }
  scope :paper, -> { where(execution_type: "paper") }
  scope :live, -> { where(execution_type: "live") }
  scope :recent, -> { order(signal_generated_at: :desc) }
  scope :by_symbol, ->(symbol) { where(symbol: symbol) }
  scope :by_direction, ->(direction) { where(direction: direction) }
  scope :simulated, -> { where(simulated: true) }
  scope :not_simulated, -> { where(simulated: false) }

  def signal_metadata_hash
    return {} if signal_metadata.blank?

    JSON.parse(signal_metadata)
  rescue JSON::ParserError
    {}
  end

  def execution_metadata_hash
    return {} if execution_metadata.blank?

    JSON.parse(execution_metadata)
  rescue JSON::ParserError
    {}
  end

  def executed?
    executed == true
  end

  def not_executed?
    !executed?
  end

  def pending_approval?
    execution_status == "pending_approval"
  end

  def failed?
    execution_status == "failed"
  end

  def long?
    direction == "long"
  end

  def short?
    direction == "short"
  end

  def paper_trading?
    execution_type == "paper"
  end

  def live_trading?
    execution_type == "live"
  end

  def insufficient_balance?
    execution_reason&.include?("Insufficient") || execution_reason&.include?("balance")
  end

  def risk_limit_exceeded?
    execution_reason&.include?("risk") || execution_reason&.include?("limit")
  end

  def simulated?
    simulated == true
  end

  def simulation_metadata_hash
    return {} if simulation_metadata.blank?

    JSON.parse(simulation_metadata)
  rescue JSON::ParserError
    {}
  end

  def simulate!(end_date: nil)
    TradingSignals::Simulator.simulate(self, end_date: end_date)
  end

  def simulated_profit?
    simulated_pnl&.positive? == true
  end

  def simulated_loss?
    simulated_pnl&.negative? == true
  end

  def simulated_breakeven?
    simulated_pnl&.zero? == true
  end

  def mark_as_executed!(execution_type:, order: nil, paper_position: nil, metadata: {})
    update!(
      executed: true,
      execution_type: execution_type,
      execution_status: "executed",
      execution_reason: "Successfully executed",
      order: order,
      paper_position: paper_position,
      execution_attempted_at: execution_attempted_at || Time.current,
      execution_completed_at: Time.current,
      execution_metadata: execution_metadata_hash.merge(metadata).to_json,
    )
  end

  def mark_as_not_executed!(reason:, error: nil, metadata: {})
    update!(
      executed: false,
      execution_status: "not_executed",
      execution_reason: reason,
      execution_error: error,
      execution_attempted_at: execution_attempted_at || Time.current,
      execution_metadata: execution_metadata_hash.merge(metadata).to_json,
    )
  end

  def mark_as_failed!(reason:, error:, metadata: {})
    update!(
      executed: false,
      execution_status: "failed",
      execution_reason: reason,
      execution_error: error,
      execution_attempted_at: execution_attempted_at || Time.current,
      execution_metadata: execution_metadata_hash.merge(metadata).to_json,
    )
  end

  def mark_as_pending_approval!(reason:, metadata: {})
    update!(
      executed: false,
      execution_status: "pending_approval",
      execution_reason: reason,
      execution_attempted_at: execution_attempted_at || Time.current,
      execution_metadata: execution_metadata_hash.merge(metadata).to_json,
    )
  end

  def self.create_from_signal(signal, source: "screener", execution_attempted: false, balance_info: {})
    instrument = Instrument.find_by(id: signal[:instrument_id])
    return nil unless instrument

    signal_record = create!(
      instrument: instrument,
      symbol: signal[:symbol] || instrument.symbol_name,
      direction: signal[:direction].to_s,
      entry_price: signal[:entry_price],
      stop_loss: signal[:sl],
      take_profit: signal[:tp],
      quantity: signal[:qty],
      order_value: signal[:entry_price] * signal[:qty],
      confidence: signal[:confidence],
      risk_reward_ratio: signal[:rr],
      holding_days_estimate: signal[:holding_days_estimate],
      source: source,
      screener_type: "swing",
      signal_generated_at: Time.current,
      execution_attempted_at: execution_attempted ? Time.current : nil,
      signal_metadata: {
        signal: signal,
        indicators: signal[:metadata]&.dig(:indicators),
        created_at: Time.current,
      }.to_json,
      required_balance: balance_info[:required] || (signal[:entry_price] * signal[:qty]),
      available_balance: balance_info[:available],
      balance_shortfall: balance_info[:shortfall],
      balance_type: balance_info[:type] || "live_account",
    )

    signal_record
  end
end
