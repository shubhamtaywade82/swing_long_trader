# Screener UI Columns - Final Design

## ✅ Column Separation Complete

### Screener Tab (Informational - Candidates Only)

**Purpose**: Market state view - "What the market looks like"

**Columns Shown**:
1. **Rank** - Row number
2. **Symbol** - Stock ticker
3. **Score** - Combined screener score (0-100)
4. **Base Score** - Base technical score (hidden by default, toggleable)
5. **MTF Score** - Multi-timeframe score (hidden by default, toggleable)
6. **Price** - Current LTP (live updates)
7. **RSI** - Relative Strength Index (hidden by default, toggleable)
8. **ADX** - Average Directional Index (hidden by default, toggleable)
9. **ATR%** - Average True Range percentage (hidden by default, toggleable)
10. **Trend** - Trend state (Bullish/Bearish indicators)
11. **Dist EMA20** - Distance from EMA20 % (hidden by default, toggleable)
12. **Dist EMA50** - Distance from EMA50 % (hidden by default, toggleable)

**Columns NOT Shown** (per contract):
- ❌ Setup Status
- ❌ Entry Zone
- ❌ SL (Stop Loss)
- ❌ TP (Take Profit)
- ❌ Quantity
- ❌ Risk Amount
- ❌ Risk-Reward Ratio
- ❌ Recommendation
- ❌ AI Confidence

**Table**: `_screener_candidates_table.html.erb`

---

### Recommendations Tab (Actionable - Ready to Trade)

**Purpose**: Actionable view - "What you can trade"

**Columns Shown**:
1. **#** - Row number
2. **Symbol** - Stock ticker
3. **Score** - Combined screener score
4. **Setup Status** - READY, WAIT_PULLBACK, WAIT_BREAKOUT, NOT_READY
5. **Price** - Current LTP (live updates)
6. **Entry Zone** - Entry price/zone from trade plan
7. **SL** - Stop Loss price
8. **TP** - Take Profit price
9. **Quantity** - Recommended quantity
10. **Risk ₹** - Risk amount and capital used
11. **RR** - Risk-Reward ratio
12. **AI Confidence** - AI confidence score (if available)
13. **Recommendation** - Actionable recommendation text

**Table**: `_screener_table_compact.html.erb`

---

## 📋 Tab Structure

### Tab Order
1. **Screener** (Informational) - Shows all candidates
2. **Recommendations** (Actionable) - Shows ready-to-trade candidates
3. **Bullish Stocks** (Informational) - Shows bullish candidates
4. **Bearish / Wait** (Informational) - Shows bearish/wait candidates
5. **Flag Stocks** (Informational) - Shows candidates already in positions

### Default Active Tab
- **Screener** tab is active by default (emphasizes informational view first)
- **Screener** tab is first in list (emphasizes it's the base view)

---

## 🎯 Column Comparison

| Column         | Screener Tab   | Recommendations Tab |
| -------------- | -------------- | ------------------- |
| Symbol         | ✅              | ✅                   |
| Score          | ✅              | ✅                   |
| Price          | ✅              | ✅                   |
| Trend State    | ✅              | ❌                   |
| Setup Status   | ❌              | ✅                   |
| Entry Zone     | ❌              | ✅                   |
| SL             | ❌              | ✅                   |
| TP             | ❌              | ✅                   |
| Quantity       | ❌              | ✅                   |
| Risk Amount    | ❌              | ✅                   |
| RR             | ❌              | ✅                   |
| AI Confidence  | ❌              | ✅                   |
| Recommendation | ❌              | ✅                   |
| RSI            | ✅ (toggleable) | ❌                   |
| ADX            | ✅ (toggleable) | ❌                   |
| ATR%           | ✅ (toggleable) | ❌                   |
| Dist EMA20     | ✅ (toggleable) | ❌                   |
| Dist EMA50     | ✅ (toggleable) | ❌                   |

---

## ✅ Contract Compliance

### Screener Tab
- ✅ Only shows candidate generation data
- ✅ No setup classification
- ✅ No trade plans
- ✅ No capital-aware data
- ✅ Clear labeling: "Market Scan – Candidates Only"
- ✅ Informational message

### Recommendations Tab
- ✅ Shows actionable data
- ✅ Setup Status prominently displayed
- ✅ Trade Plan columns (Entry, SL, TP) clearly separated
- ✅ Quantity and Risk Amount shown
- ✅ AI Confidence displayed
- ✅ Recommendation text shown
- ✅ Clear labeling: "Ready to Trade"
- ✅ Actionable message

---

## 📝 Files

### Swing Screener
1. `app/views/screeners/_screener_candidates_table.html.erb` - Informational table
2. `app/views/screeners/_screener_table_compact.html.erb` - Actionable table (Recommendations)
3. `app/views/screeners/_screener_table.html.erb` - Full table (conditional columns)
4. `app/views/screeners/swing.html.erb` - Main view with tabs

### Longterm Screener
1. `app/views/screeners/_screener_candidates_table.html.erb` - Informational table (shared)
2. `app/views/screeners/_longterm_screener_table_compact.html.erb` - Actionable table (Recommendations)
3. `app/views/screeners/_longterm_screener_table.html.erb` - Full table (conditional columns)
4. `app/views/screeners/longterm.html.erb` - Main view with tabs

---

## 📊 Longterm Screener Specifics

### Recommendations Tab (Longterm)
**Purpose**: Actionable accumulation view - "What you can accumulate"

**Columns Shown**:
1. **#** - Row number
2. **Symbol** - Stock ticker
3. **Score** - Combined screener score
4. **Setup Status** - ACCUMULATE, WAIT_DIP, WAIT_BREAKOUT, NOT_READY
5. **Price** - Current LTP (live updates)
6. **Buy Zone** - Accumulation buy zone price
7. **Invalid Level** - Price level that invalidates the setup
8. **Allocation %** - Percentage of capital to allocate
9. **Allocation ₹** - Absolute amount to allocate
10. **Horizon** - Time horizon in months
11. **AI Confidence** - AI confidence score (if available)
12. **Recommendation** - Actionable recommendation text

**Differences from Swing**:
- Uses accumulation plans instead of trade plans
- Shows allocation percentage and amount
- Shows time horizon instead of risk-reward
- Focuses on long-term accumulation strategy

---

## ✅ Summary

The UI now properly separates:
- **Screener tabs** = Informational columns only (both Swing and Longterm)
- **Recommendations tab** = Actionable columns only
  - **Swing**: Trade plans (Entry, SL, TP, Quantity, Risk, RR)
  - **Longterm**: Accumulation plans (Buy Zone, Invalid Level, Allocation, Horizon)

Clear visual separation prevents confusion and follows the Screener Contract.
