# Manual Verification Steps

This document outlines manual verification steps that require user action and cannot be automated.

## PHASE 4 — Instrument Import Verification

### Step 1: Test Instrument Import

**Prerequisites:**
- DhanHQ credentials configured in `.env` file
- Database migrations completed (`rails db:migrate`)
- Environment variables set (see `docs/ENV_SETUP.md`)

**Steps:**
1. Ensure DhanHQ credentials are set:
   ```bash
   # Check if credentials are set
   echo $DHANHQ_CLIENT_ID
   echo $DHANHQ_ACCESS_TOKEN
   ```

2. Run the import command:
   ```bash
   rails instruments:import
   ```

3. Expected output:
   - Import progress messages
   - Total instruments imported
   - Breakdown by exchange (NSE, BSE)
   - Breakdown by segment (Equity, Index)

4. Verify success:
   - Check for "Import completed successfully" message
   - Note the total instrument count
   - Verify no error messages

**Troubleshooting:**
- If import fails with authentication error, verify DhanHQ credentials
- If CSV download fails, check network connectivity
- If database errors occur, verify migrations are up to date

### Step 2: Verify Import Status

**Steps:**
1. Run the status check:
   ```bash
   rails instruments:status
   ```

2. Expected output:
   - Last import timestamp
   - Import age (should be recent)
   - Import duration
   - Total instruments count
   - Status: OK or STALE

3. Verify key instruments exist:
   ```bash
   rails console
   ```
   ```ruby
   # Check for key index instruments
   Instrument.find_by(symbol_name: 'NIFTY')
   Instrument.find_by(symbol_name: 'BANKNIFTY')
   Instrument.find_by(symbol_name: 'SENSEX')

   # Check counts
   Instrument.count
   Instrument.segment_index.count
   Instrument.segment_equity.count
   ```

**Success Criteria:**
- Status shows "OK" (not STALE)
- Key index instruments (NIFTY, BANKNIFTY) are present
- Total instrument count is reasonable (typically 1000+ for equity + index)

---

## PHASE 6 — SMC Structure Validation (Optional)

### Validate SMC Structure

**Purpose:** Verify that Smart Money Concepts (BOS, CHOCH, Order Blocks, FVGs, Mitigation Blocks) are correctly detecting market structure.

**Steps:**
1. Load an instrument with sufficient historical data:
   ```ruby
   instrument = Instrument.find_by(symbol_name: 'RELIANCE')
   daily_series = instrument.load_daily_candles(limit: 100)
   ```

2. Test SMC components:
   ```ruby
   # Test BOS detection
   bos_result = Smc::Bos.detect(daily_series.candles)
   puts bos_result

   # Test CHOCH detection
   choch_result = Smc::Choch.detect(daily_series.candles)
   puts choch_result

   # Test Order Block detection
   ob_result = SMC::OrderBlock.detect(daily_series.candles)
   puts ob_result

   # Test FVG detection
   fvg_result = SMC::FairValueGap.detect(daily_series.candles)
   puts fvg_result

   # Test Mitigation Block detection
   mb_result = SMC::MitigationBlock.detect(daily_series.candles)
   puts mb_result

   # Test Structure Validator
   validation = SMC::StructureValidator.validate(daily_series.candles)
   puts validation
   ```

3. Verify results:
   - BOS should detect structure breaks
   - CHOCH should detect character changes
   - Order Blocks should identify institutional zones
   - FVGs should find price imbalances
   - Mitigation Blocks should find rejection zones
   - Structure Validator should provide overall assessment

**Success Criteria:**
- All SMC components return valid results
- Detections align with visual chart analysis
- Structure Validator provides meaningful scores

---

## PHASE 10 — Backtesting Validation

### Ensure Backtest Signals Match Live Signals

**Purpose:** Verify that signals generated during backtesting match what would be generated in live trading.

**Steps:**
1. Run a backtest for a specific date range:
   ```bash
   rails backtest:swing[2024-01-01,2024-03-31,100000]
   ```

2. Note the signals generated during backtest

3. Manually verify a few signals by:
   - Loading the same instrument and date range
   - Running the strategy engine manually:
     ```ruby
     instrument = Instrument.find_by(symbol_name: 'RELIANCE')
     daily_series = instrument.load_daily_candles(limit: 100)
     weekly_series = instrument.load_weekly_candles(limit: 52)

     result = Strategies::Swing::Engine.call(
       instrument: instrument,
       daily_series: daily_series,
       weekly_series: weekly_series
     )
     puts result
     ```

4. Compare:
   - Entry prices should match
   - Stop loss levels should match
   - Take profit levels should match
   - Direction should match
   - Confidence scores should match

**Success Criteria:**
- Backtest signals match manual engine calls for same dates
- No discrepancies in entry/exit logic
- Position sizing calculations are consistent

### Test Walk-Forward Logic (No Look-Ahead Bias)

**Purpose:** Verify that walk-forward analysis correctly prevents look-ahead bias.

**Steps:**
1. Run walk-forward analysis:
   ```ruby
   instruments = Instrument.where(symbol_name: ['RELIANCE', 'TCS']).limit(2)

   result = Backtesting::WalkForward.call(
     instruments: instruments,
     from_date: 1.year.ago.to_date,
     to_date: Date.today,
     initial_capital: 100_000,
     window_type: :rolling,
     in_sample_days: 180,
     out_of_sample_days: 60,
     backtester_class: Backtesting::SwingBacktester
   )
   ```

2. Verify no look-ahead bias:
   - Check that in-sample data is not used for out-of-sample validation
   - Verify that signals are generated only using data available up to that date
   - Confirm that future data is never accessed

3. Manual verification:
   - Pick a specific date from the walk-forward windows
   - Manually check what data would have been available at that date
   - Verify the backtest only uses data up to that date

**Success Criteria:**
- Out-of-sample performance is calculated correctly
- No future data leakage
- Degradation metrics are reasonable

---

## PHASE 12 — Execution (Optional)

### Manual Testing Steps for Order Execution

**Note:** These steps require a DhanHQ paper trading account or live account. Use with caution.

1. **Enable Dry-Run Mode:**
   ```bash
   export DRY_RUN=true
   ```

2. **Test Order Placement:**
   - Run strategy executor in dry-run mode
   - Verify orders are logged but not sent
   - Check order logs for correct parameters

3. **Test Idempotency:**
   - Attempt to place the same order twice
   - Verify duplicate prevention works
   - Check order audit trail

4. **Test Risk Limits:**
   - Attempt to place orders exceeding limits
   - Verify rejection with appropriate error messages
   - Check exposure calculations

5. **Test Circuit Breaker:**
   - Simulate multiple order failures
   - Verify circuit breaker activates
   - Check that orders are blocked when circuit is open

---

## General Verification Checklist

### Before Production Deployment

- [ ] All manual verification steps completed
- [ ] Instrument import verified and working
- [ ] Backtest signals validated against live signals
- [ ] Walk-forward analysis verified (no look-ahead bias)
- [ ] SMC structure validation working (if enabled)
- [ ] Order execution tested in dry-run mode (if implementing Phase 12)
- [ ] All environment variables configured
- [ ] Database migrations completed
- [ ] Test suite passing
- [ ] Documentation reviewed

---

## Notes

- Manual verification steps cannot be automated as they require:
  - External API credentials (DhanHQ)
  - Human judgment (signal validation)
  - Visual inspection (chart analysis)
  - Risk assessment (order execution)

- These steps should be performed:
  - After initial setup
  - Before production deployment
  - Periodically to ensure system integrity
  - After major code changes

- Keep records of verification results for audit purposes.

