# Trading Agent Architecture Design

**Status:** Design Proposal  
**Date:** 2025-01-XX  
**Author:** System Architect Analysis

---

## Executive Summary

This document proposes a production-grade **Trading Agent Architecture** that evolves the existing swing/long-term screener system into a deterministic, risk-aware trading agent with optional LLM reasoning layer.

**Core Principles:**
- Deterministic logic FIRST, AI SECOND
- System must work even if LLM is OFF
- LLM can only REVIEW, never DECIDE
- Fully testable and backtestable
- Incremental migration without breaking existing functionality

---

## 1. Repository Architecture Map

### Current System Components

#### **Screening Layer** (`app/services/screeners/`)
- `SwingScreener` - Screens universe, calculates indicators, scores candidates
- `LongtermScreener` - Multi-timeframe analysis (1W, 1D, 1H)
- `SetupDetector` - Determines READY vs WAIT vs NOT_READY status
- `TradePlanBuilder` - Generates entry/SL/TP/RR/quantity for READY setups
- `LongtermSetupDetector` - Accumulation setup detection
- `LongtermTradePlanBuilder` - Long-term accumulation plans
- `AIEvaluator` - LLM-based ranking (confidence, risk, avoid flags)

**Output:** `ScreenerResult` records with:
- `score` (0-100)
- `setup_status` (READY/WAIT_PULLBACK/WAIT_BREAKOUT/NOT_READY/IN_POSITION)
- `trade_plan` (entry_price, stop_loss, take_profit, risk_reward, quantity)
- `indicators` (EMA, RSI, MACD, ADX, Supertrend, ATR)
- `metadata` (trend_alignment, volatility, momentum, multi_timeframe)

#### **Indicator Layer** (`app/services/indicators/`)
- `Calculator` - RSI, MACD, ADX wrappers
- `SupertrendIndicator` - Trend direction
- `AdxIndicator` - Trend strength
- `RsiIndicator` - Momentum
- `MacdIndicator` - Momentum confirmation
- `BaseIndicator` - Common interface

**Data Source:** `CandleSeries` (from `CandleSeriesRecord` table)

#### **Market Data Layer** (`app/services/market_data/`, `app/services/market_hub/`)
- `LtpCache` - Redis cache for LTP (Last Traded Price)
- `BulkLtpFetcher` - REST API batch fetcher
- `WebsocketTickStreamer` - Real-time DhanHQ WebSocket → Redis Pub/Sub → ActionCable
- `LtpBroadcaster` - ActionCable broadcaster
- `LtpPubsubListener` - Redis Pub/Sub listener

**Real-time Flow:**
```
DhanHQ WebSocket → WebsocketTickStreamer → Redis Pub/Sub → LtpPubsubListener → ActionCable → Frontend
```

#### **Strategy Layer** (`app/services/strategies/swing/`)
- `Engine` - Validates entry conditions, checks SMC structure
- `Evaluator` - Wraps Engine with candle loading
- `SignalBuilder` - Builds trading signals
- `Executor` - Executes signals (paper/live)

#### **Portfolio & Risk Layer** (`app/services/paper_trading/`, `app/services/portfolio/`)
- `Portfolio` - Capital allocation, position tracking
- `RiskManager` - Daily risk limits (2% per day, max 2 trades)
- `Executor` - Paper trade execution
- `Position` - Open position tracking
- `Ledger` - Trade history

**Models:**
- `CapitalAllocationPortfolio` - Capital buckets (swing/long-term)
- `SwingPosition` - Open swing positions
- `LongTermHolding` - Long-term holdings

#### **Order Management** (`app/services/orders/`, `app/services/dhan/`)
- `Approval` - Manual approval/rejection workflow
- `Orders` - DhanHQ REST API integration
- `Positions` - Position sync from broker
- `Balance` - Account balance

#### **AI Services** (`app/services/ai/`, `app/services/ollama/`, `app/services/openai/`)
- `UnifiedService` - Auto-detects provider (OpenAI → Ollama fallback)
- `Ollama::Service` - Local LLM (llama3.2, mistral, etc.)
- `Openai::Service` - GPT-4o-mini (with cost tracking)

**Current Usage:**
- `Screeners::AIEvaluator` - Evaluates candidates, assigns confidence/risk/avoid flags
- Returns JSON: `{confidence: 6.5-10, risk: "low/medium/high", holding_days: 5-15, avoid: false, comment: "..."}`

#### **Data Models**
- `ScreenerResult` - Stores screener output (score, indicators, trade_plan, ai_confidence)
- `ScreenerRun` - Tracks screener execution (metrics, health)
- `Instrument` - Stock metadata (symbol, security_id, exchange_segment)
- `CandleSeriesRecord` - OHLCV data (timeframe: 1D, 1W, 1H, 15M)
- `TradingSignal` - Generated signals (entry_price, qty, direction)
- `Order` - Order records (pending/approved/rejected/executed)

---

## 2. Gaps & Risks in Current Design

### **Critical Gaps**

#### **Gap 1: No Formal Trade Recommendation Contract**
**Current State:**
- Screener outputs `ScreenerResult` with `trade_plan` hash
- Trade plan format varies between swing/long-term
- No standardized DTO for downstream systems

**Risk:**
- Inconsistent data structure across layers
- Hard to validate trade recommendations
- Difficult to add new decision layers

**Impact:** HIGH

#### **Gap 2: No Deterministic Trade Decision Engine**
**Current State:**
- `SetupDetector` determines READY vs WAIT
- `TradePlanBuilder` generates plans
- No centralized validation/filtering layer

**Risk:**
- Weak setups can pass through
- No unified risk rules enforcement
- Cannot backtest decision logic independently

**Impact:** HIGH

#### **Gap 3: LLM Directly Influences Trade Selection**
**Current State:**
- `AIEvaluator` filters candidates by `confidence >= 6.5` and `avoid != true`
- AI output directly affects which trades are shown

**Risk:**
- System breaks if LLM fails
- No deterministic fallback
- Cannot test without LLM

**Impact:** MEDIUM (mitigated by `@enabled` flag, but still risky)

#### **Gap 4: No Automation Mode Abstraction**
**Current State:**
- Paper trading executor exists
- Order approval workflow exists
- No unified mode (advisory/semi-auto/full-auto)

**Risk:**
- Cannot easily switch between modes
- No kill-switch mechanism
- No max loss tracking

**Impact:** MEDIUM

#### **Gap 5: No Trade Recommendation → Order Bridge**
**Current State:**
- `TradePlanBuilder` generates plans
- `TradingSignal` exists but not always created
- No clear path: ScreenerResult → Trade Recommendation → Order

**Risk:**
- Manual intervention required
- Inconsistent signal generation
- Hard to automate

**Impact:** MEDIUM

### **Architectural Risks**

1. **Tight Coupling:** Screeners directly call AI services
2. **No Separation of Concerns:** Decision logic mixed with data fetching
3. **Inconsistent Error Handling:** Some services return `{success: false}`, others raise
4. **No Circuit Breaker:** LLM failures can cascade
5. **Missing Observability:** Limited metrics on decision quality

---

## 3. Trade Recommendation DTO

### **Proposed Structure**

```ruby
# app/trading/trade_recommendation.rb

module Trading
  class TradeRecommendation
    # Core identification
    attr_reader :symbol, :instrument_id, :timeframe
    
    # Direction & bias
    attr_reader :bias  # :long, :short, :avoid
    
    # Entry & exit levels
    attr_reader :entry_price, :entry_zone
    attr_reader :stop_loss
    attr_reader :target_prices  # Array of [price, probability]
    
    # Risk metrics
    attr_reader :risk_reward, :risk_per_share, :risk_amount
    attr_reader :confidence_score  # 0-100 (deterministic)
    attr_reader :quantity
    
    # Invalidation & conditions
    attr_reader :invalidation_conditions  # Array of strings
    attr_reader :entry_conditions  # Hash
    
    # Reasoning (deterministic + optional LLM)
    attr_reader :reasoning  # Array of strings
    attr_reader :llm_review  # Optional LLM output
    
    # Metadata
    attr_reader :source  # :screener, :manual, :backtest
    attr_reader :screener_run_id
    attr_reader :analyzed_at
    
    # Validation
    def valid?
      bias != :avoid &&
        entry_price&.positive? &&
        stop_loss&.positive? &&
        risk_reward >= 2.0 &&
        confidence_score >= 60.0
    end
    
    def to_hash
      {
        symbol: symbol,
        instrument_id: instrument_id,
        timeframe: timeframe,
        bias: bias,
        entry_price: entry_price,
        entry_zone: entry_zone,
        stop_loss: stop_loss,
        target_prices: target_prices,
        risk_reward: risk_reward,
        risk_per_share: risk_per_share,
        risk_amount: risk_amount,
        confidence_score: confidence_score,
        quantity: quantity,
        invalidation_conditions: invalidation_conditions,
        entry_conditions: entry_conditions,
        reasoning: reasoning,
        llm_review: llm_review,
        source: source,
        screener_run_id: screener_run_id,
        analyzed_at: analyzed_at,
      }
    end
  end
end
```

### **Mapping from Existing Data**

#### **From `ScreenerResult` (Swing)**
```ruby
# app/trading/adapters/screener_result_adapter.rb

module Trading
  module Adapters
    class ScreenerResultAdapter
      def self.to_trade_recommendation(screener_result)
        return nil unless screener_result.setup_status == "READY"
        
        trade_plan = screener_result.metadata_hash[:trade_plan]
        return nil unless trade_plan
        
        TradeRecommendation.new(
          symbol: screener_result.symbol,
          instrument_id: screener_result.instrument_id,
          timeframe: "swing",
          bias: :long,  # Current system is long-only
          entry_price: trade_plan[:entry_price],
          entry_zone: trade_plan[:entry_zone],
          stop_loss: trade_plan[:stop_loss],
          target_prices: [
            [trade_plan[:take_profit], 0.7],  # 70% probability
          ],
          risk_reward: trade_plan[:risk_reward],
          risk_per_share: trade_plan[:risk_per_share],
          risk_amount: trade_plan[:risk_amount],
          confidence_score: screener_result.score,  # 0-100
          quantity: trade_plan[:quantity],
          invalidation_conditions: [
            screener_result.metadata_hash[:invalidate_if],
          ].compact,
          entry_conditions: screener_result.metadata_hash[:entry_conditions] || {},
          reasoning: build_reasoning(screener_result),
          llm_review: build_llm_review(screener_result),
          source: :screener,
          screener_run_id: screener_result.screener_run_id,
          analyzed_at: screener_result.analyzed_at,
        )
      end
      
      private
      
      def self.build_reasoning(screener_result)
        indicators = screener_result.indicators_hash
        reasoning = []
        
        reasoning << "EMA20 > EMA50 (bullish trend)" if indicators.dig(:ema20) && indicators.dig(:ema50) && indicators[:ema20] > indicators[:ema50]
        reasoning << "Supertrend bullish" if indicators.dig(:supertrend, :direction) == "bullish"
        reasoning << "ADX #{indicators[:adx].round(1)} (strong trend)" if indicators[:adx] && indicators[:adx] > 25
        reasoning << "RSI #{indicators[:rsi].round(1)} (momentum)" if indicators[:rsi]
        
        reasoning
      end
      
      def self.build_llm_review(screener_result)
        return nil unless screener_result.ai_confidence
        
        {
          confidence: screener_result.ai_confidence,
          risk: screener_result.ai_risk,
          holding_days: screener_result.ai_holding_days,
          comment: screener_result.ai_comment,
          avoid: screener_result.ai_avoid,
        }
      end
    end
  end
end
```

#### **From `ScreenerResult` (Long-term)**
```ruby
# Similar adapter for long-term accumulation plans
# Uses accumulation_plan instead of trade_plan
# Bias: :accumulate (new type)
# Timeframe: "longterm"
```

---

## 4. Deterministic Trade Decision Engine

### **Architecture**

```
┌─────────────────────────────────────────────────────────────┐
│           Trade Recommendation (DTO)                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│     Decision Engine (Deterministic)                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  1. Validator (required fields, data quality)        │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  2. Risk Rules Enforcer (RR, volatility, position)   │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  3. Setup Filter (trend, momentum, structure)        │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  4. Portfolio Constraints (capital, max positions)    │  │
│  └──────────────────────────────────────────────────────┘  │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │  APPROVED │ REJECTED  │
            └──────────────────────┘
```

### **Implementation**

```ruby
# app/trading/decision_engine/engine.rb

module Trading
  module DecisionEngine
    class Engine < ApplicationService
      # Configuration
      MIN_RISK_REWARD = 2.0
      MIN_CONFIDENCE = 60.0
      MAX_VOLATILITY_PCT = 8.0  # ATR % of price
      MAX_POSITIONS_PER_SYMBOL = 1
      MAX_DAILY_RISK_PCT = 2.0
      
      def self.call(trade_recommendation:, portfolio: nil, market_data: nil)
        new(
          trade_recommendation: trade_recommendation,
          portfolio: portfolio,
          market_data: market_data,
        ).call
      end
      
      def initialize(trade_recommendation:, portfolio: nil, market_data: nil)
        @recommendation = trade_recommendation
        @portfolio = portfolio
        @market_data = market_data || fetch_market_data
      end
      
      def call
        # Step 1: Validate structure
        validation = Validator.call(@recommendation)
        return validation unless validation[:approved]
        
        # Step 2: Enforce risk rules
        risk_check = RiskRulesEnforcer.call(
          recommendation: @recommendation,
          portfolio: @portfolio,
        )
        return risk_check unless risk_check[:approved]
        
        # Step 3: Filter weak setups
        setup_check = SetupFilter.call(
          recommendation: @recommendation,
          market_data: @market_data,
        )
        return setup_check unless setup_check[:approved]
        
        # Step 4: Check portfolio constraints
        portfolio_check = PortfolioConstraints.call(
          recommendation: @recommendation,
          portfolio: @portfolio,
        )
        return portfolio_check unless portfolio_check[:approved]
        
        {
          approved: true,
          recommendation: @recommendation,
          decision_path: [
            validation[:reason],
            risk_check[:reason],
            setup_check[:reason],
            portfolio_check[:reason],
          ],
        }
      end
      
      private
      
      def fetch_market_data
        # Fetch current LTP, volatility, etc.
        {
          current_price: @recommendation.entry_price,  # Fallback
          volatility: calculate_volatility,
        }
      end
      
      def calculate_volatility
        # Calculate ATR % from indicators if available
        nil  # Placeholder
      end
    end
  end
end
```

### **Sub-components**

#### **1. Validator**
```ruby
# app/trading/decision_engine/validator.rb

module Trading
  module DecisionEngine
    class Validator
      def self.call(recommendation)
        errors = []
        
        errors << "Missing entry_price" unless recommendation.entry_price&.positive?
        errors << "Missing stop_loss" unless recommendation.stop_loss&.positive?
        errors << "Risk-reward < #{MIN_RISK_REWARD}" if recommendation.risk_reward < MIN_RISK_REWARD
        errors << "Confidence < #{MIN_CONFIDENCE}" if recommendation.confidence_score < MIN_CONFIDENCE
        errors << "Invalid bias" unless %i[long short].include?(recommendation.bias)
        
        if errors.any?
          { approved: false, reason: "Validation failed", errors: errors }
        else
          { approved: true, reason: "Valid structure" }
        end
      end
    end
  end
end
```

#### **2. RiskRulesEnforcer**
```ruby
# app/trading/decision_engine/risk_rules_enforcer.rb

module Trading
  module DecisionEngine
    class RiskRulesEnforcer
      def self.call(recommendation:, portfolio: nil)
        # Check risk-reward ratio
        return { approved: false, reason: "RR too low" } if recommendation.risk_reward < 2.0
        
        # Check volatility (if available)
        # Reject if ATR % > 8%
        
        # Check daily risk limit (if portfolio available)
        if portfolio
          daily_risk = calculate_daily_risk(portfolio)
          risk_limit = portfolio.total_capital * (MAX_DAILY_RISK_PCT / 100.0)
          return { approved: false, reason: "Daily risk limit exceeded" } if daily_risk + recommendation.risk_amount > risk_limit
        end
        
        { approved: true, reason: "Risk rules passed" }
      end
      
      private
      
      def self.calculate_daily_risk(portfolio)
        # Sum risk_amount of all open positions opened today
        today = Date.current
        portfolio.open_positions
                 .where("opened_at >= ?", today.beginning_of_day)
                 .sum(:risk_amount) || 0
      end
    end
  end
end
```

#### **3. SetupFilter**
```ruby
# app/trading/decision_engine/setup_filter.rb

module Trading
  module DecisionEngine
    class SetupFilter
      def self.call(recommendation:, market_data:)
        # Reject if price extended too far (already handled by SetupDetector, but double-check)
        # Reject if trend weakening
        # Reject if consolidation detected
        
        { approved: true, reason: "Setup quality acceptable" }
      end
    end
  end
end
```

#### **4. PortfolioConstraints**
```ruby
# app/trading/decision_engine/portfolio_constraints.rb

module Trading
  module DecisionEngine
    class PortfolioConstraints
      def self.call(recommendation:, portfolio: nil)
        return { approved: true, reason: "No portfolio constraints" } unless portfolio
        
        # Check max positions per symbol
        existing = portfolio.open_positions.where(instrument_id: recommendation.instrument_id).count
        return { approved: false, reason: "Already in position" } if existing >= MAX_POSITIONS_PER_SYMBOL
        
        # Check capital availability
        required_capital = recommendation.entry_price * recommendation.quantity
        return { approved: false, reason: "Insufficient capital" } if required_capital > portfolio.available_capital
        
        { approved: true, reason: "Portfolio constraints satisfied" }
      end
    end
  end
end
```

### **Integration Point**

```ruby
# app/services/screeners/final_selector.rb (existing, enhance)

module Screeners
  class FinalSelector < ApplicationService
    def self.call(candidates:, screener_run_id: nil, portfolio: nil)
      new(candidates: candidates, screener_run_id: screener_run_id, portfolio: portfolio).call
    end
    
    def call
      # Convert candidates to TradeRecommendations
      recommendations = @candidates.map do |candidate|
        adapter = Trading::Adapters::ScreenerResultAdapter
        adapter.to_trade_recommendation(candidate)
      end.compact
      
      # Run through Decision Engine
      approved = recommendations.filter_map do |rec|
        result = Trading::DecisionEngine::Engine.call(
          trade_recommendation: rec,
          portfolio: @portfolio,
        )
        result[:approved] ? rec : nil
      end
      
      approved
    end
  end
end
```

---

## 5. LLM Integration Layer

### **Design Principles**

1. **LLM can only REVIEW, never DECIDE**
2. **Strict JSON output with fallback**
3. **System continues if LLM fails**
4. **Same interface for Ollama and OpenAI**

### **Architecture**

```
┌─────────────────────────────────────────────────────────────┐
│     Approved Trade Recommendation (from Decision Engine)    │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│     LLM Review Service (Optional)                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Base Interface (abstract)                            │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Ollama Implementation                                 │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  OpenAI Implementation                                 │  │
│  └──────────────────────────────────────────────────────┘  │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │  LLM Review Output   │
            │  - approve/reject    │
            │  - confidence adj    │
            │  - reasoning         │
            └──────────────────────┘
```

### **Interface Definition**

```ruby
# app/llm/base.rb

module LLM
  class Base
    def self.review_trade(trade_recommendation)
      raise NotImplementedError, "Subclass must implement review_trade"
    end
    
    protected
    
    def build_prompt(recommendation)
      <<~PROMPT
        You are a quantitative trading analyst reviewing a trade recommendation.
        
        Trade Details:
        - Symbol: #{recommendation.symbol}
        - Entry: ₹#{recommendation.entry_price}
        - Stop Loss: ₹#{recommendation.stop_loss}
        - Target: ₹#{recommendation.target_prices.first&.first}
        - Risk-Reward: #{recommendation.risk_reward}R
        - Confidence: #{recommendation.confidence_score}/100
        
        Deterministic Reasoning:
        #{recommendation.reasoning.join("\n")}
        
        Market Context:
        - Timeframe: #{recommendation.timeframe}
        - Analyzed at: #{recommendation.analyzed_at}
        
        Your Task:
        Review this trade and respond with STRICT JSON only:
        {
          "approved": true/false,
          "confidence_adjustment": -10 to +10 (adjust deterministic confidence),
          "reasoning": "Brief explanation",
          "risk_narrative": "low/medium/high",
          "holding_period_days": 5-15,
          "avoid": false
        }
        
        Rules:
        - approved: true means you agree with the deterministic decision
        - approved: false means you disagree (but system may still proceed)
        - confidence_adjustment: Adjust the deterministic confidence score
        - avoid: true means strongly recommend avoiding this trade
        
        Respond with JSON only, no other text.
      PROMPT
    end
    
    def parse_response(response_content)
      # Extract JSON from response (handle markdown code blocks)
      json_match = response_content.match(/```json\s*(\{.*?\})\s*```/m) ||
                   response_content.match(/(\{.*\})/m)
      
      return default_response unless json_match
      
      JSON.parse(json_match[1])
    rescue JSON::ParserError
      default_response
    end
    
    def default_response
      {
        "approved" => true,
        "confidence_adjustment" => 0,
        "reasoning" => "LLM parsing failed, using deterministic decision",
        "risk_narrative" => "medium",
        "holding_period_days" => 10,
        "avoid" => false,
      }
    end
  end
end
```

### **Ollama Implementation**

```ruby
# app/llm/ollama.rb

module LLM
  class Ollama < Base
    DEFAULT_MODEL = "llama3.2"
    DEFAULT_TEMPERATURE = 0.3
    
    def self.review_trade(trade_recommendation)
      new.review_trade(trade_recommendation)
    end
    
    def review_trade(recommendation)
      prompt = build_prompt(recommendation)
      
      # Use existing Ollama::Service
      result = Ollama::Service.call(
        prompt: prompt,
        model: ENV.fetch("OLLAMA_MODEL", DEFAULT_MODEL),
        temperature: DEFAULT_TEMPERATURE,
        cache: true,
      )
      
      return default_review unless result[:success]
      
      parsed = parse_response(result[:content])
      build_review_output(parsed, recommendation)
    rescue StandardError => e
      Rails.logger.error("[LLM::Ollama] Review failed: #{e.message}")
      default_review
    end
    
    private
    
    def build_review_output(parsed, recommendation)
      {
        approved: parsed["approved"] != false,  # Default to true if missing
        confidence_adjustment: parsed["confidence_adjustment"] || 0,
        adjusted_confidence: [
          0,
          100,
          recommendation.confidence_score + (parsed["confidence_adjustment"] || 0),
        ].sort[1],  # Clamp to 0-100
        reasoning: parsed["reasoning"] || "No reasoning provided",
        risk_narrative: parsed["risk_narrative"] || "medium",
        holding_period_days: parsed["holding_period_days"] || 10,
        avoid: parsed["avoid"] == true,
        provider: "ollama",
      }
    end
    
    def default_review
      {
        approved: true,
        confidence_adjustment: 0,
        adjusted_confidence: nil,  # Use deterministic only
        reasoning: "LLM unavailable, using deterministic decision",
        risk_narrative: "medium",
        holding_period_days: 10,
        avoid: false,
        provider: "ollama",
        error: true,
      }
    end
  end
end
```

### **OpenAI Implementation**

```ruby
# app/llm/openai.rb

module LLM
  class OpenAI < Base
    DEFAULT_MODEL = "gpt-4o-mini"
    DEFAULT_TEMPERATURE = 0.3
    
    def self.review_trade(trade_recommendation)
      new.review_trade(trade_recommendation)
    end
    
    def review_trade(recommendation)
      prompt = build_prompt(recommendation)
      
      # Use existing Openai::Service
      result = Openai::Service.call(
        prompt: prompt,
        model: DEFAULT_MODEL,
        temperature: DEFAULT_TEMPERATURE,
        max_tokens: 200,
        cache: true,
      )
      
      return default_review unless result[:success]
      
      parsed = parse_response(result[:content])
      build_review_output(parsed, recommendation)
    rescue StandardError => e
      Rails.logger.error("[LLM::OpenAI] Review failed: #{e.message}")
      default_review
    end
    
    private
    
    def build_review_output(parsed, recommendation)
      {
        approved: parsed["approved"] != false,
        confidence_adjustment: parsed["confidence_adjustment"] || 0,
        adjusted_confidence: [
          0,
          100,
          recommendation.confidence_score + (parsed["confidence_adjustment"] || 0),
        ].sort[1],
        reasoning: parsed["reasoning"] || "No reasoning provided",
        risk_narrative: parsed["risk_narrative"] || "medium",
        holding_period_days: parsed["holding_period_days"] || 10,
        avoid: parsed["avoid"] == false,
        provider: "openai",
      }
    end
    
    def default_review
      {
        approved: true,
        confidence_adjustment: 0,
        adjusted_confidence: nil,
        reasoning: "LLM unavailable, using deterministic decision",
        risk_narrative: "medium",
        holding_period_days: 10,
        avoid: false,
        provider: "openai",
        error: true,
      }
    end
  end
end
```

### **Unified LLM Service**

```ruby
# app/llm/unified_service.rb

module LLM
  class UnifiedService
    def self.review_trade(trade_recommendation, provider: nil)
      provider ||= determine_provider
      
      case provider.to_s.downcase
      when "ollama", "local"
        Ollama.review_trade(trade_recommendation)
      when "openai"
        OpenAI.review_trade(trade_recommendation)
      else
        # Auto-detect: try OpenAI first, fallback to Ollama
        result = OpenAI.review_trade(trade_recommendation)
        return result unless result[:error]
        
        Ollama.review_trade(trade_recommendation)
      end
    end
    
    private
    
    def self.determine_provider
      ENV["LLM_PROVIDER"] || AlgoConfig.fetch(%i[trading llm provider]) || "auto"
    end
  end
end
```

### **Integration with Decision Engine**

```ruby
# app/trading/decision_engine/engine.rb (enhance)

module Trading
  module DecisionEngine
    class Engine
      def call
        # ... existing deterministic checks ...
        
        # Optional: LLM review (if enabled)
        if llm_enabled?
          llm_review = LLM::UnifiedService.review_trade(@recommendation)
          
          # Apply LLM adjustments (but don't override deterministic rejection)
          if llm_review[:avoid] == true
            return {
              approved: false,
              reason: "LLM flagged as avoid: #{llm_review[:reasoning]}",
              llm_review: llm_review,
            }
          end
          
          # Adjust confidence (optional, for display only)
          @recommendation.llm_review = llm_review
        end
        
        {
          approved: true,
          recommendation: @recommendation,
          decision_path: [...],
        }
      end
      
      private
      
      def llm_enabled?
        AlgoConfig.fetch(%i[trading llm enabled]) != false
      end
    end
  end
end
```

---

## 6. Automation Modes & Risk Controls

### **Mode Definitions**

```ruby
# app/trading/modes/mode.rb

module Trading
  module Modes
    class Mode
      ADVISORY = "advisory"  # Show recommendations only, no execution
      SEMI_AUTOMATED = "semi_automated"  # Generate orders, require approval
      FULLY_AUTOMATED = "fully_automated"  # Auto-execute (with kill-switches)
      
      attr_reader :name, :config
      
      def initialize(name, config = {})
        @name = name
        @config = config
      end
      
      def advisory?
        @name == ADVISORY
      end
      
      def semi_automated?
        @name == SEMI_AUTOMATED
      end
      
      def fully_automated?
        @name == FULLY_AUTOMATED
      end
      
      def can_execute?
        semi_automated? || fully_automated?
      end
    end
  end
end
```

### **Risk Controls**

```ruby
# app/trading/risk_controls/kill_switch.rb

module Trading
  module RiskControls
    class KillSwitch
      # Kill-switch rules
      MAX_DAILY_LOSS_PCT = 5.0  # Stop trading if daily loss > 5%
      MAX_CONSECUTIVE_LOSSES = 3  # Stop after 3 consecutive losses
      MAX_POSITIONS = 5  # Max open positions
      MARKET_HOURS_ONLY = true  # Only trade during market hours
      
      def self.check(portfolio: nil, mode: nil)
        new(portfolio: portfolio, mode: mode).check
      end
      
      def initialize(portfolio: nil, mode: nil)
        @portfolio = portfolio
        @mode = mode
      end
      
      def check
        checks = [
          check_daily_loss,
          check_consecutive_losses,
          check_max_positions,
          check_market_hours,
          check_manual_override,
        ]
        
        failed = checks.find { |c| c[:blocked] }
        
        if failed
          {
            active: true,
            blocked: true,
            reason: failed[:reason],
            checks: checks,
          }
        else
          {
            active: true,
            blocked: false,
            checks: checks,
          }
        end
      end
      
      private
      
      def check_daily_loss
        return { blocked: false } unless @portfolio
        
        today_pnl = calculate_daily_pnl
        max_loss = @portfolio.total_capital * (MAX_DAILY_LOSS_PCT / 100.0)
        
        if today_pnl < -max_loss
          {
            blocked: true,
            reason: "Daily loss limit exceeded: ₹#{today_pnl.abs.round(2)} >= ₹#{max_loss.round(2)}",
          }
        else
          { blocked: false }
        end
      end
      
      def check_consecutive_losses
        return { blocked: false } unless @portfolio
        
        recent_trades = @portfolio.closed_positions
                                  .order(closed_at: :desc)
                                  .limit(MAX_CONSECUTIVE_LOSSES)
        
        return { blocked: false } if recent_trades.count < MAX_CONSECUTIVE_LOSSES
        
        all_losses = recent_trades.all? { |t| t.realized_pnl < 0 }
        
        if all_losses
          {
            blocked: true,
            reason: "#{MAX_CONSECUTIVE_LOSSES} consecutive losses detected",
          }
        else
          { blocked: false }
        end
      end
      
      def check_max_positions
        return { blocked: false } unless @portfolio
        
        open_count = @portfolio.open_positions.count
        
        if open_count >= MAX_POSITIONS
          {
            blocked: true,
            reason: "Max positions reached: #{open_count}/#{MAX_POSITIONS}",
          }
        else
          { blocked: false }
        end
      end
      
      def check_market_hours
        return { blocked: false } unless MARKET_HOURS_ONLY
        
        now = Time.current.in_time_zone("Asia/Kolkata")
        return { blocked: false } unless now.wday.between?(1, 5)  # Mon-Fri
        
        market_open = now.change(hour: 9, min: 15, sec: 0)
        market_close = now.change(hour: 15, min: 30, sec: 0)
        
        if now < market_open || now > market_close
          {
            blocked: true,
            reason: "Outside market hours (#{market_open.strftime('%H:%M')} - #{market_close.strftime('%H:%M')})",
          }
        else
          { blocked: false }
        end
      end
      
      def check_manual_override
        # Check Redis/DB for manual kill-switch flag
        override = Rails.cache.read("trading_kill_switch:manual")
        
        if override == true
          {
            blocked: true,
            reason: "Manual kill-switch activated",
          }
        else
          { blocked: false }
        end
      end
      
      def calculate_daily_pnl
        today = Date.current
        @portfolio.closed_positions
                  .where("closed_at >= ?", today.beginning_of_day)
                  .sum(:realized_pnl) || 0
      end
    end
  end
end
```

### **Mode Execution Flow**

```ruby
# app/trading/executor.rb

module Trading
  class Executor < ApplicationService
    def self.execute(trade_recommendation:, mode: nil, portfolio: nil)
      new(
        trade_recommendation: trade_recommendation,
        mode: mode || current_mode,
        portfolio: portfolio,
      ).execute
    end
    
    def execute
      # Step 1: Check kill-switches
      kill_switch = RiskControls::KillSwitch.check(
        portfolio: @portfolio,
        mode: @mode,
      )
      
      return {
        success: false,
        error: "Kill-switch active: #{kill_switch[:reason]}",
        kill_switch: kill_switch,
      } if kill_switch[:blocked]
      
      # Step 2: Run Decision Engine
      decision = DecisionEngine::Engine.call(
        trade_recommendation: @trade_recommendation,
        portfolio: @portfolio,
      )
      
      return {
        success: false,
        error: "Decision engine rejected: #{decision[:reason]}",
        decision: decision,
      } unless decision[:approved]
      
      # Step 3: Mode-specific execution
      case @mode.name
      when Modes::Mode::ADVISORY
        execute_advisory
      when Modes::Mode::SEMI_AUTOMATED
        execute_semi_automated
      when Modes::Mode::FULLY_AUTOMATED
        execute_fully_automated
      else
        { success: false, error: "Unknown mode: #{@mode.name}" }
      end
    end
    
    private
    
    def execute_advisory
      {
        success: true,
        mode: "advisory",
        recommendation: @trade_recommendation,
        message: "Recommendation generated (advisory mode - no execution)",
      }
    end
    
    def execute_semi_automated
      # Create order, mark as pending approval
      order = create_order(requires_approval: true)
      
      {
        success: true,
        mode: "semi_automated",
        order: order,
        message: "Order created, pending approval",
      }
    end
    
    def execute_fully_automated
      # Create order, auto-approve, execute
      order = create_order(requires_approval: false)
      Orders::Approval.approve(order.id, approved_by: "system")
      
      {
        success: true,
        mode: "fully_automated",
        order: order,
        message: "Order auto-executed",
      }
    end
    
    def create_order(requires_approval:)
      Order.create!(
        instrument_id: @trade_recommendation.instrument_id,
        symbol: @trade_recommendation.symbol,
        transaction_type: @trade_recommendation.bias == :long ? "BUY" : "SELL",
        order_type: "MARKET",  # Or "LIMIT" based on config
        quantity: @trade_recommendation.quantity,
        price: @trade_recommendation.entry_price,
        stop_loss: @trade_recommendation.stop_loss,
        target_price: @trade_recommendation.target_prices.first&.first,
        requires_approval: requires_approval,
        metadata: {
          trade_recommendation: @trade_recommendation.to_hash,
          source: "trading_agent",
        },
      )
    end
    
    def self.current_mode
      mode_name = Rails.cache.read("trading_mode:current") || Modes::Mode::ADVISORY
      config = AlgoConfig.fetch(%i[trading modes]) || {}
      Modes::Mode.new(mode_name, config[mode_name.to_sym] || {})
    end
  end
end
```

---

## 7. Incremental Migration Plan

### **Phase 1: Foundation (Week 1-2)**

**Goal:** Add Trade Recommendation DTO without breaking existing system

**Tasks:**
1. Create `app/trading/trade_recommendation.rb` (DTO class)
2. Create `app/trading/adapters/screener_result_adapter.rb` (converter)
3. Add adapter to `ScreenerResult` model: `to_trade_recommendation` method
4. Add feature flag: `config/trading.yml` → `dto_enabled: false`
5. Test: Verify adapter converts existing `ScreenerResult` correctly

**Testing:**
- Unit tests for adapter
- Integration test: Screener → Adapter → DTO
- Verify no UI changes required

**Rollback:** Disable feature flag

---

### **Phase 2: Decision Engine (Week 3-4)**

**Goal:** Add deterministic decision engine as optional layer

**Tasks:**
1. Create `app/trading/decision_engine/` directory structure
2. Implement `Engine`, `Validator`, `RiskRulesEnforcer`, `SetupFilter`, `PortfolioConstraints`
3. Add feature flag: `decision_engine_enabled: false`
4. Integrate into `Screeners::FinalSelector` (optional, behind flag)
5. Add metrics/logging for decision paths

**Testing:**
- Unit tests for each component
- Integration test: ScreenerResult → Decision Engine → Approved/Rejected
- Backtest: Run historical data through engine
- Verify existing screeners still work

**Rollback:** Disable feature flag

---

### **Phase 3: LLM Integration Refactor (Week 5-6)**

**Goal:** Refactor AI services to use new LLM review interface

**Tasks:**
1. Create `app/llm/base.rb`, `app/llm/ollama.rb`, `app/llm/openai.rb`
2. Create `app/llm/unified_service.rb`
3. Refactor `Screeners::AIEvaluator` to use new interface (backward compatible)
4. Add LLM review to Decision Engine (optional, behind flag)
5. Migrate existing AI evaluation prompts to new format

**Testing:**
- Unit tests for LLM services
- Integration test: Trade Recommendation → LLM Review → Output
- Verify existing AI ranking still works
- Test fallback when LLM fails

**Rollback:** Keep old `AIEvaluator` code, disable new LLM integration

---

### **Phase 4: Automation Modes (Week 7-8)**

**Goal:** Add mode abstraction and risk controls

**Tasks:**
1. Create `app/trading/modes/mode.rb`
2. Create `app/trading/risk_controls/kill_switch.rb`
3. Create `app/trading/executor.rb`
4. Add mode selection UI (admin panel)
5. Add kill-switch controls (Redis flags)

**Testing:**
- Unit tests for modes and kill-switches
- Integration test: Advisory mode → Semi-auto → Full-auto
- Test kill-switch activation/deactivation
- Verify existing paper trading still works

**Rollback:** Default to advisory mode

---

### **Phase 5: Integration & Polish (Week 9-10)**

**Goal:** Wire everything together, add observability

**Tasks:**
1. Create `app/trading/orchestrator.rb` (main entry point)
2. Add metrics: Decision Engine approval rate, LLM review rate, execution rate
3. Add logging: Decision paths, LLM reasoning, kill-switch activations
4. Add monitoring dashboard (Grafana/CloudWatch)
5. Documentation: Architecture diagram, API docs

**Testing:**
- End-to-end test: Screener → Decision Engine → LLM Review → Execution
- Load test: Handle 100+ recommendations per run
- Failure test: LLM down, kill-switch active, etc.

**Rollback:** Disable orchestrator, use existing screeners

---

### **Migration Checklist**

- [ ] Phase 1: DTO created and tested
- [ ] Phase 2: Decision Engine created and tested
- [ ] Phase 3: LLM integration refactored
- [ ] Phase 4: Automation modes implemented
- [ ] Phase 5: Full integration complete
- [ ] All existing tests pass
- [ ] New tests added and passing
- [ ] Documentation updated
- [ ] Monitoring/alerting configured
- [ ] Rollback plan tested

---

## Summary

This architecture provides:

1. **Deterministic Foundation:** Decision Engine validates all trades before LLM review
2. **Optional LLM Layer:** LLM can review but never override deterministic rejection
3. **Flexible Automation:** Three modes (advisory/semi-auto/full-auto) with kill-switches
4. **Incremental Migration:** Each phase can be deployed independently
5. **Production-Ready:** Error handling, fallbacks, observability built-in

**Next Steps:**
1. Review this design
2. Identify weak spots
3. Lock final architecture
4. Begin Phase 1 implementation
