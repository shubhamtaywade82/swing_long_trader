# frozen_string_literal: true

module Trading
  # Finite State Machine for Trade Lifecycle
  # Explicit states prevent ambiguity and ensure proper tracking
  class TradeLifecycle
    # State definitions
    PROPOSED = "PROPOSED"
    APPROVED = "APPROVED"
    QUEUED = "QUEUED"
    ENTERED = "ENTERED"
    MANAGING = "MANAGING"
    EXITED = "EXITED"
    CANCELLED = "CANCELLED"
    INVALIDATED = "INVALIDATED"

    # Valid states
    VALID_STATES = [
      PROPOSED,
      APPROVED,
      QUEUED,
      ENTERED,
      MANAGING,
      EXITED,
      CANCELLED,
      INVALIDATED,
    ].freeze

    # Terminal states (no further transitions)
    TERMINAL_STATES = [
      EXITED,
      CANCELLED,
      INVALIDATED,
    ].freeze

    # Valid state transitions
    TRANSITIONS = {
      PROPOSED => [APPROVED, CANCELLED, INVALIDATED],
      APPROVED => [QUEUED, CANCELLED, INVALIDATED],
      QUEUED => [ENTERED, CANCELLED, INVALIDATED],
      ENTERED => [MANAGING, CANCELLED, INVALIDATED],
      MANAGING => [EXITED, CANCELLED, INVALIDATED],
      EXITED => [], # Terminal
      CANCELLED => [], # Terminal
      INVALIDATED => [], # Terminal
    }.freeze

    attr_reader :current_state
    attr_reader :history
    attr_reader :created_at
    attr_reader :updated_at

    def initialize(initial_state: PROPOSED, created_at: Time.current)
      @current_state = validate_state(initial_state)
      @history = [
        {
          state: @current_state,
          timestamp: created_at,
          reason: "Initial state",
        },
      ]
      @created_at = created_at
      @updated_at = created_at
    end

    # Transition to new state
    def transition_to(new_state, reason: nil)
      new_state = validate_state(new_state)

      # Check if transition is valid
      unless can_transition_to?(new_state)
        raise InvalidTransitionError,
              "Cannot transition from #{@current_state} to #{new_state}. " \
              "Valid transitions: #{TRANSITIONS[@current_state].join(', ')}"
      end

      # Check if already in terminal state
      if terminal?
        raise InvalidTransitionError,
              "Cannot transition from terminal state #{@current_state}"
      end

      # Perform transition
      previous_state = @current_state
      @current_state = new_state
      @updated_at = Time.current

      # Add to history
      @history << {
        state: new_state,
        timestamp: @updated_at,
        reason: reason || "Transitioned from #{previous_state}",
        previous_state: previous_state,
      }

      self
    end

    # State checkers
    def proposed?
      current_state == PROPOSED
    end

    def approved?
      current_state == APPROVED
    end

    def queued?
      current_state == QUEUED
    end

    def entered?
      current_state == ENTERED
    end

    def managing?
      current_state == MANAGING
    end

    def exited?
      current_state == EXITED
    end

    def cancelled?
      current_state == CANCELLED
    end

    def invalidated?
      current_state == INVALIDATED
    end

    def terminal?
      TERMINAL_STATES.include?(@current_state)
    end

    def active?
      [APPROVED, QUEUED, ENTERED, MANAGING].include?(@current_state)
    end

    def can_transition_to?(new_state)
      new_state = validate_state(new_state)
      TRANSITIONS[@current_state]&.include?(new_state) || false
    end

    # Convenience transition methods
    def approve!(reason: nil)
      transition_to(APPROVED, reason: reason || "Approved by Decision Engine")
    end

    def queue!(reason: nil)
      transition_to(QUEUED, reason: reason || "Queued for execution")
    end

    def enter!(reason: nil)
      transition_to(ENTERED, reason: reason || "Order executed, position entered")
    end

    def start_managing!(reason: nil)
      transition_to(MANAGING, reason: reason || "Position management started")
    end

    def exit!(reason: nil)
      transition_to(EXITED, reason: reason || "Position exited")
    end

    def cancel!(reason: nil)
      transition_to(CANCELLED, reason: reason || "Trade cancelled")
    end

    def invalidate!(reason: nil)
      transition_to(INVALIDATED, reason: reason || "Trade invalidated")
    end

    # Serialization
    def to_hash
      {
        current_state: current_state,
        history: history,
        created_at: created_at.iso8601,
        updated_at: updated_at.iso8601,
        terminal: terminal?,
        active: active?,
      }
    end

    def to_json(*args)
      to_hash.to_json(*args)
    end

    # Build from hash (for deserialization)
    def self.from_hash(hash)
      lifecycle = new(
        initial_state: hash[:current_state] || hash["current_state"] || PROPOSED,
        created_at: parse_timestamp(hash[:created_at] || hash["created_at"]),
      )

      # Restore history if available
      if hash[:history] || hash["history"]
        history = hash[:history] || hash["history"]
        lifecycle.instance_variable_set(:@history, history.map(&:deep_symbolize_keys))
        lifecycle.instance_variable_set(:@updated_at, parse_timestamp(hash[:updated_at] || hash["updated_at"]))
      end

      lifecycle
    end

    private

    def validate_state(state)
      state_str = state.to_s.upcase
      unless VALID_STATES.include?(state_str)
        raise InvalidStateError, "Invalid state: #{state_str}. Valid states: #{VALID_STATES.join(', ')}"
      end
      state_str
    end

    def self.parse_timestamp(timestamp)
      return Time.current unless timestamp

      timestamp.is_a?(Time) ? timestamp : Time.parse(timestamp.to_s)
    rescue StandardError
      Time.current
    end
  end

  # Custom exceptions
  class InvalidStateError < StandardError; end

  class InvalidTransitionError < StandardError; end
end
