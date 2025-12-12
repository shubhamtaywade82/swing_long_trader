# System Flow Diagrams

**Visual representation of how the system works**

---

## Complete Daily Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    DAILY AUTOMATION FLOW                        │
└─────────────────────────────────────────────────────────────────┘

07:30 IST - CANDLE INGESTION
├─ Candles::DailyIngestorJob
├─ Fetches from DhanHQ API
├─ Stores in candle_series_records
└─ Updates all instruments

07:40 IST - SCREENING
├─ Screeners::SwingScreenerJob
├─ Analyzes instruments
├─ Calculates indicators
├─ Scores candidates (0-100)
├─ Selects top candidates
├─ Sends Telegram (top 10)
└─ Triggers AnalysisJob (if enabled)

07:45 IST - SIGNAL GENERATION
├─ Strategies::Swing::AnalysisJob
├─ Evaluates top candidates
├─ Generates trading signals
├─ Creates TradingSignal records
├─ Sends Telegram alerts
└─ Signals ready for execution

09:00-15:30 IST - MARKET HOURS (Every 30 minutes)

├─ ENTRY MONITORING
│  ├─ Strategies::Swing::EntryMonitorJob
│  ├─ Checks entry conditions
│  ├─ Generates signals
│  ├─ Executes trades (if conditions met)
│  └─ Sends notifications
│
├─ EXIT MONITORING
│  ├─ LIVE: Strategies::Swing::ExitMonitorJob
│  │  ├─ Checks open orders
│  │  ├─ Checks SL/TP conditions
│  │  ├─ Places exit orders
│  │  └─ Sends notifications
│  │
│  └─ PAPER: PaperTrading::Simulator.check_exits
│     ├─ Updates position prices
│     ├─ Checks SL/TP conditions
│     ├─ Closes positions
│     ├─ Calculates P&L
│     └─ Sends notifications
│
└─ HEALTH MONITORING
   ├─ MonitorJob
   ├─ Checks system health
   └─ Sends alerts if issues
```

---

## Signal Execution Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    SIGNAL EXECUTION FLOW                        │
└─────────────────────────────────────────────────────────────────┘

SIGNAL GENERATED
│
├─ Creates TradingSignal record
│  ├─ executed: false
│  ├─ signal details stored
│  └─ balance info captured
│
└─ EXECUTION ATTEMPTED
   │
   ├─ Balance Check
   │  ├─ LIVE: DhanHQ API
   │  └─ PAPER: PaperPortfolio.available_capital
   │
   ├─ Risk Limits Check
   │  ├─ Max position size
   │  ├─ Max total exposure
   │  └─ Daily loss limits
   │
   └─ EXECUTION RESULT
      │
      ├─ ✅ SUCCESS
      │  ├─ LIVE MODE:
      │  │  ├─ Places order via DhanHQ
      │  │  ├─ Creates Order record
      │  │  ├─ Updates TradingSignal (executed: true, order_id)
      │  │  └─ Sends entry notification
      │  │
      │  └─ PAPER MODE:
      │     ├─ Creates PaperPosition record
      │     ├─ Reserves capital
      │     ├─ Updates TradingSignal (executed: true, paper_position_id)
      │     └─ Sends entry notification
      │
      └─ ❌ FAILED
         ├─ Updates TradingSignal (executed: false, reason)
         ├─ Sends recommendation notification (if balance issue)
         └─ Stores balance shortfall
```

---

## Portfolio Management Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                  PORTFOLIO MANAGEMENT FLOW                       │
└─────────────────────────────────────────────────────────────────┘

LIVE TRADING PORTFOLIO
│
├─ Balance Source: DhanHQ API
├─ Positions: Orders table
├─ P&L: From order execution
└─ No separate portfolio table

─────────────────────────────────────────────────────────────────

PAPER TRADING PORTFOLIO
│
├─ INITIAL STATE
│  ├─ capital: ₹100,000
│  ├─ reserved_capital: ₹0
│  ├─ available_capital: ₹100,000
│  └─ total_equity: ₹100,000
│
├─ ENTRY (₹10,000 position)
│  ├─ capital: ₹100,000 (unchanged)
│  ├─ reserved_capital: ₹10,000 (+₹10,000)
│  ├─ available_capital: ₹90,000 (-₹10,000)
│  └─ total_equity: ₹100,000 (no unrealized yet)
│
├─ PRICE MOVES (to ₹11,000)
│  ├─ capital: ₹100,000 (unchanged)
│  ├─ reserved_capital: ₹10,000 (unchanged)
│  ├─ unrealized_pnl: ₹1,000
│  └─ total_equity: ₹101,000 (capital + unrealized)
│
└─ EXIT (at ₹11,000)
   ├─ capital: ₹101,000 (+₹1,000 profit)
   ├─ reserved_capital: ₹0 (-₹10,000)
   ├─ available_capital: ₹101,000
   ├─ realized_pnl: ₹1,000
   └─ total_equity: ₹101,000
```

---

## Position Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                    POSITION LIFECYCLE                            │
└─────────────────────────────────────────────────────────────────┘

LIVE TRADING POSITION
│
├─ ORDER PLACED
│  ├─ Order record created (status: "pending")
│  ├─ TradingSignal updated (executed: true, order_id)
│  └─ Notification sent
│
├─ ORDER EXECUTED
│  ├─ Order status: "executed"
│  ├─ Position exists in DhanHQ
│  └─ Exit monitoring starts
│
└─ EXIT TRIGGERED
   ├─ Exit order placed
   ├─ Order status: "executed"
   └─ Notification sent

─────────────────────────────────────────────────────────────────

PAPER TRADING POSITION
│
├─ POSITION CREATED
│  ├─ PaperPosition created (status: "open")
│  ├─ Capital reserved
│  ├─ TradingSignal updated (executed: true, paper_position_id)
│  └─ Notification sent
│
├─ PRICE UPDATES
│  ├─ Current price updated from candles
│  ├─ Unrealized P&L calculated
│  └─ Portfolio equity updated
│
└─ EXIT TRIGGERED
   ├─ Position closed (status: "closed")
   ├─ P&L calculated and added to capital
   ├─ Capital reservation released
   └─ Notification sent

─────────────────────────────────────────────────────────────────

SIMULATION
│
├─ SIGNAL NOT EXECUTED
│  └─ TradingSignal (executed: false)
│
├─ SIMULATION RUN
│  ├─ Loads historical candles
│  ├─ Simulates entry → exit
│  └─ Calculates P&L
│
└─ RESULTS STORED
   ├─ TradingSignal updated (simulated: true)
   ├─ simulated_pnl stored
   └─ simulated_exit_price/date stored
```

---

## Balance Check Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    BALANCE CHECK FLOW                            │
└─────────────────────────────────────────────────────────────────┘

SIGNAL GENERATED
│
└─ EXECUTION ATTEMPTED
   │
   ├─ LIVE MODE
   │  ├─ Dhan::Balance.check_available_balance
   │  ├─ Calls DhanHQ API
   │  ├─ Gets real account balance
   │  └─ Compares with required amount
   │
   └─ PAPER MODE
      ├─ Checks PaperPortfolio.available_capital
      ├─ available_capital = capital - reserved_capital
      └─ Compares with required amount
      │
      └─ RESULT
         │
         ├─ ✅ SUFFICIENT
         │  └─ Trade executed
         │
         └─ ❌ INSUFFICIENT
            ├─ TradingSignal updated (executed: false)
            ├─ Balance info stored (required, available, shortfall)
            └─ Telegram notification sent (with full recommendation)
```

---

## Notification Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    NOTIFICATION FLOW                             │
└─────────────────────────────────────────────────────────────────┘

SIGNAL GENERATED
│
├─ If balance insufficient
│  └─ 📊 Trading Recommendation notification
│     ├─ Full signal details
│     ├─ Balance information
│     └─ Shortfall amount
│
└─ EXECUTION ATTEMPTED
   │
   ├─ ✅ SUCCESS
   │  ├─ LIVE: 📊 Order Placed notification
   │  └─ PAPER: 📘 Paper Trade Executed notification
   │
   └─ ❌ FAILED
      └─ ❌ Error notification (if not balance-related)

EXIT TRIGGERED
│
├─ LIVE MODE
│  └─ 📊 Exit Order Placed notification
│
└─ PAPER MODE
   └─ ✅/❌ Paper Trade Exited notification
      ├─ Entry/exit prices
      ├─ P&L
      └─ Holding days

DAILY SUMMARY (Paper Trading)
│
└─ 📊 Daily Paper Trading Summary
   ├─ Portfolio equity
   ├─ Realized/unrealized P&L
   ├─ Open/closed positions
   └─ Available capital
```

---

## Complete Automation Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│              COMPLETE AUTOMATION ARCHITECTURE                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    RAILS APPLICATION                         │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         SOLIDQUEUE WORKER (REQUIRED!)                │  │
│  │  Reads config/recurring.yml                          │  │
│  │  Executes scheduled jobs                              │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   DATA       │  │   ANALYSIS    │  │   EXECUTION   │     │
│  │              │  │              │  │              │     │
│  │ - Ingestion  │  │ - Screening  │  │ - Live       │     │
│  │ - Storage    │  │ - Signals    │  │ - Paper      │     │
│  │ - Updates    │  │ - AI Ranking │  │ - Monitoring  │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      DATABASE                                │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   SIGNALS    │  │   ORDERS     │  │  POSITIONS   │     │
│  │              │  │              │  │              │     │
│  │ All modes    │  │ Live only    │  │ Paper only   │     │
│  │ Execution    │  │ DhanHQ sync  │  │ Virtual      │     │
│  │ Simulation   │  │ Status track │  │ Price update │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  PORTFOLIOS  │  │   CANDLES    │  │   METRICS    │     │
│  │              │  │              │  │              │     │
│  │ Paper only   │  │ Historical   │  │ P&L tracking │     │
│  │ Virtual      │  │ Daily/Weekly  │  │ Win rate     │     │
│  │ Capital mgmt │  │ Indicators   │  │ Drawdown     │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  EXTERNAL SERVICES                           │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   DHANHQ     │  │   TELEGRAM    │  │   OPENAI     │     │
│  │              │  │              │  │              │     │
│  │ - Orders     │  │ - Alerts     │  │ - AI Ranking │     │
│  │ - Balance    │  │ - Errors     │  │ - Analysis    │     │
│  │ - Prices     │  │ - Summary    │  │              │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

---

## Mode Comparison Visual

```
┌─────────────────────────────────────────────────────────────┐
│                    MODE COMPARISON                          │
└─────────────────────────────────────────────────────────────┘

LIVE TRADING 🟢
├─ Money: REAL (DhanHQ account)
├─ Orders: REAL (placed via API)
├─ Positions: REAL (in DhanHQ)
├─ Balance: REAL (from API)
├─ P&L: REAL (from execution)
└─ Risk: REAL MONEY AT RISK

PAPER TRADING 📘
├─ Money: VIRTUAL (PaperPortfolio)
├─ Orders: VIRTUAL (PaperPosition records)
├─ Positions: VIRTUAL (in database)
├─ Balance: VIRTUAL (calculated)
├─ P&L: CALCULATED (from prices)
└─ Risk: NO REAL RISK

SIMULATION 🎯
├─ Money: NONE
├─ Orders: NONE
├─ Positions: NONE
├─ Balance: SHOWS WHAT WAS NEEDED
├─ P&L: CALCULATED (historical)
└─ Risk: NONE (analysis only)
```

---

## Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                      DATA FLOW                               │
└─────────────────────────────────────────────────────────────┘

DHANHQ API
    │
    ├─→ Candle Data → candle_series_records
    │                    │
    │                    ├─→ Indicators (EMA, RSI, etc.)
    │                    │
    │                    └─→ Screeners → Candidates
    │                                      │
    │                                      └─→ Analysis → Signals
    │                                                      │
    │                                                      ├─→ LIVE: Orders → DhanHQ
    │                                                      │
    │                                                      ├─→ PAPER: PaperPositions → Database
    │                                                      │
    │                                                      └─→ SIMULATION: TradingSignals → Database
    │
    └─→ Balance → Balance Check → Execution Decision
```

---

## Key Takeaways

1. **Three Modes:** Live (real), Paper (virtual), Simulation (analysis)
2. **Portfolio Management:** Live uses DhanHQ, Paper uses PaperPortfolio, Simulation uses none
3. **Position Tracking:** Live tracks orders, Paper tracks positions, Simulation tracks none
4. **Balance:** Live from API, Paper from portfolio, Simulation shows what was needed
5. **Automation:** Requires SolidQueue worker + scheduled jobs
6. **Notifications:** Sent for all events (entries, exits, errors, recommendations)
7. **Simulation:** Manual operation to analyze missed opportunities

---

**For detailed explanations, see [Complete System Guide](COMPLETE_SYSTEM_GUIDE.md)**
