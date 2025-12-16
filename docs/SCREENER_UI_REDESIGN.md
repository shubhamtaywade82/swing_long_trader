# Screener UI Redesign - Contract Compliance

## ✅ Completed

### 1. Created Screener Candidates Table Partial
- **File**: `app/views/screeners/_screener_candidates_table.html.erb`
- **Purpose**: Shows ONLY informational data (candidates only, no actionable data)
- **Columns Shown**:
  - Rank
  - Symbol
  - Score (Combined)
  - Base Score (hidden by default, toggleable)
  - MTF Score (hidden by default, toggleable)
  - Price (LTP)
  - RSI (hidden by default, toggleable)
  - ADX (hidden by default, toggleable)
  - ATR% (hidden by default, toggleable)
  - Trend State (Bullish/Bearish indicators)
  - Distance from EMA20 (hidden by default, toggleable)
  - Distance from EMA50 (hidden by default, toggleable)

- **Columns NOT Shown** (per contract):
  - ❌ Setup Status
  - ❌ Entry Zone
  - ❌ SL (Stop Loss)
  - ❌ TP (Take Profit)
  - ❌ Quantity
  - ❌ Risk Amount
  - ❌ Risk-Reward Ratio
  - ❌ Recommendation

---

### 2. Updated Main View Structure
- **File**: `app/views/screeners/swing.html.erb`
- **Changes**:
  - Added "Screener" tab as first tab (informational view)
  - Renamed "Recommendations" tab (actionable view)
  - Updated headings:
    - Screener tab: "Market Scan – Candidates Only" with info message
    - Recommendations tab: "Ready to Trade" with actionable message
  - Removed "Buy Recommendations" heading
  - Removed "Buy Only" filter buttons

---

### 3. Updated Table Partials
- **File**: `app/views/screeners/_screener_table.html.erb`
- **Changes**:
  - Setup Status column only shown when `show_recommendation: true`
  - Trade Plan columns (Entry, SL, TP, RR, Qty, Risk) only shown when `show_recommendation: true`
  - Added contract comments explaining when columns are shown

- **File**: `app/views/screeners/_screener_table_compact.html.erb`
- **Status**: Already correct - only used for Recommendations tab with actionable data

---

## 📋 Tab Structure

### Screener Tab (Informational)
- **Label**: "Screener" with candidate count badge
- **Heading**: "Market Scan – Candidates Only"
- **Message**: "Informational view showing market state. No trading instructions."
- **Table**: Uses `_screener_candidates_table` partial
- **Columns**: Symbol, Score, Price, Trend State, Technical Indicators (toggleable)

---

### Recommendations Tab (Actionable)
- **Label**: "Recommendations" with count badge
- **Heading**: "Ready to Trade"
- **Message**: "Actionable recommendations with entry, SL, TP, and quantity."
- **Table**: Uses `_screener_table_compact` partial
- **Columns**: Symbol, Score, Setup Status, Price, Trade Plan (Entry/SL/TP), Qty, Risk, RR, AI Confidence

---

### Bullish Stocks Tab (Informational)
- **Label**: "Bullish Stocks" with count badge
- **Heading**: "Bullish Candidates"
- **Message**: "Informational view showing bullish market state."
- **Table**: Uses `_screener_candidates_table` partial
- **Columns**: Same as Screener tab (informational only)

---

### Bearish / Wait Tab (Informational)
- **Label**: "Bearish / Wait" with count badge
- **Heading**: "Bearish / Wait Candidates"
- **Message**: "Informational view showing bearish or wait-state stocks."
- **Table**: Uses `_screener_candidates_table` partial
- **Columns**: Same as Screener tab (informational only)

---

### Flag Stocks Tab (Informational)
- **Label**: "Flag Stocks (In Positions)" with count badge
- **Heading**: "Stocks Already in Positions"
- **Message**: "Candidates that are already held in portfolio."
- **Table**: Uses `_screener_candidates_table` partial
- **Columns**: Same as Screener tab (informational only)

---

## ✅ Contract Compliance

### Screener Tab Compliance
- ✅ Shows only candidate generation data
- ✅ No setup status
- ✅ No trade plans
- ✅ No quantity
- ✅ No risk amounts
- ✅ No recommendations
- ✅ Clear labeling: "Market Scan – Candidates Only"
- ✅ Informational message explaining it's not actionable

### Recommendations Tab Compliance
- ✅ Shows actionable data
- ✅ Setup Status column
- ✅ Trade Plan columns (Entry, SL, TP)
- ✅ Quantity column
- ✅ Risk Amount column
- ✅ Risk-Reward Ratio column
- ✅ AI Confidence column
- ✅ Clear labeling: "Ready to Trade"
- ✅ Actionable message explaining it's ready to trade

---

## 🎯 User Experience

### Before (Violations)
- ❌ "Buy Recommendations" heading implied immediate action
- ❌ "Buy Only" button suggested trading
- ❌ Setup Status shown in all tabs
- ❌ Trade plans shown in all tabs
- ❌ Confusing mix of informational and actionable data

### After (Compliant)
- ✅ Clear separation: Screener (informational) vs Recommendations (actionable)
- ✅ Screener tab clearly labeled as "Market Scan – Candidates Only"
- ✅ Recommendations tab clearly labeled as "Ready to Trade"
- ✅ No actionable data in screener/candidates tabs
- ✅ All actionable data only in Recommendations tab

---

## 📝 Files Changed

1. ✅ `app/views/screeners/_screener_candidates_table.html.erb` - NEW (informational table)
2. ✅ `app/views/screeners/swing.html.erb` - Updated tab structure and headings
3. ✅ `app/views/screeners/_screener_table.html.erb` - Conditional columns based on `show_recommendation`
4. ✅ `app/views/screeners/_screener_table_compact.html.erb` - Added contract comment

---

## 🔍 Testing Checklist

- [ ] Screener tab shows only informational columns
- [ ] Recommendations tab shows actionable columns
- [ ] No setup status in Screener/Bullish/Bearish tabs
- [ ] No trade plans in Screener/Bullish/Bearish tabs
- [ ] No quantity/risk in Screener/Bullish/Bearish tabs
- [ ] Recommendations tab shows all actionable data
- [ ] Headings are clear and descriptive
- [ ] Info messages explain the difference between tabs

---

## ✅ Summary

The UI now properly follows the Screener Contract:

- **Screener tabs** = Informational, market state view
- **Recommendations tab** = Actionable, ready to trade view
- **Clear separation** prevents confusion
- **Contract compliance** enforced at UI level

Users can now clearly distinguish between:
1. "What the market looks like" (Screener tab)
2. "What I can trade" (Recommendations tab)
