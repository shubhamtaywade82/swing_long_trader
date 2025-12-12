# Post-Universe Verification Checklist

**After successfully verifying the shortlisted universe, follow this systematic testing workflow.**

---

## ✅ Phase 1: Data Ingestion (CRITICAL - Do This First)

### 1.1 Ingest Historical Candle Data

**Why:** Indicators, screeners, and backtesting all require historical candle data.

```bash
# Ingest daily candles (last 365 days)
rails runner "Candles::DailyIngestor.call(days_back: 365)"

# Ingest weekly candles (last 52 weeks)
rails runner "Candles::WeeklyIngestor.call(weeks_back: 52)"

# For testing, you can start with smaller ranges:
rails runner "Candles::DailyIngestor.call(days_back: 30)"  # Last 30 days
rails runner "Candles::WeeklyIngestor.call(weeks_back: 12)"  # Last 12 weeks
```

**Verification:**
```bash
# Check candle data status
rails runner "
  puts 'Daily candles: ' + CandleSeriesRecord.where(timeframe: '1D').count.to_s
  puts 'Weekly candles: ' + CandleSeriesRecord.where(timeframe: '1W').count.to_s
  puts 'Instruments with daily candles: ' + CandleSeriesRecord.where(timeframe: '1D').distinct.count(:instrument_id).to_s
  puts 'Instruments with weekly candles: ' + CandleSeriesRecord.where(timeframe: '1W').distinct.count(:instrument_id).to_s
"
```

**Expected:** At least 50+ daily candles per instrument for reliable indicators.

---

## ✅ Phase 2: Indicator Testing

### 2.1 Test All Indicators

**Why:** Verify that technical indicators are calculating correctly.

```bash
# Test all indicators
rails indicators:test

# Test specific indicators
rails indicators:test_ema
rails indicators:test_rsi
rails indicators:test_macd
rails indicators:test_supertrend
rails indicators:test_adx
rails indicators:test_atr
```

**Verification:**
- All indicators should return valid numeric values
- No errors or exceptions
- Values should be within expected ranges (e.g., RSI: 0-100, ADX: 0-100)

---

## ✅ Phase 3: Screener Testing

### 3.1 Test Swing Screener

**Why:** Verify that the screener can identify trading candidates from your universe.

```bash
# Run swing screener
rails screener:swing

# Or in Rails console for more control:
rails console
> result = Screeners::SwingScreener.call(limit: 10)
> puts result[:candidates].map { |c| "#{c[:symbol]}: score=#{c[:score]}" }
```

**Verification:**
- Screener should return candidates (may be empty if no signals)
- Each candidate should have valid score, symbol, and analysis
- Check that candidates are from your universe only

### 3.2 Test Long-Term Screener

```bash
# Run long-term screener
rails screener:longterm

# Or in Rails console:
rails console
> result = Screeners::LongtermScreener.call(limit: 10)
> puts result[:candidates].map { |c| "#{c[:symbol]}: score=#{c[:score]}" }
```

**Verification:**
- Similar to swing screener
- Should use weekly candles for analysis
- Candidates should align with long-term strategy criteria

---

## ✅ Phase 4: Strategy Engine Testing

### 4.1 Test Swing Strategy Engine

**Why:** Verify that the strategy can generate buy/sell signals.

```bash
rails console
> instrument = Instrument.find_by(symbol_name: 'RELIANCE')  # Use a symbol from your universe
> daily_series = instrument.load_daily_candles(limit: 200)
> weekly_series = instrument.load_weekly_candles(limit: 52)

> result = Strategies::Swing::Engine.call(
    instrument: instrument,
    daily_series: daily_series,
    weekly_series: weekly_series
  )

> puts "Signal: #{result[:signal]}"
> puts "Confidence: #{result[:confidence]}" if result[:confidence]
> puts "Entry: #{result[:entry_price]}" if result[:entry_price]
> puts "Stop Loss: #{result[:stop_loss]}" if result[:stop_loss]
> puts "Take Profit: #{result[:take_profit]}" if result[:take_profit]
```

**Verification:**
- Should return `{ success: true, signal: :long/:short/:hold }`
- Entry, stop loss, and take profit should be valid prices
- Confidence should be 0-100

### 4.2 Test Long-Term Strategy Engine

```bash
rails console
> instrument = Instrument.find_by(symbol_name: 'RELIANCE')
> daily_series = instrument.load_daily_candles(limit: 365)
> weekly_series = instrument.load_weekly_candles(limit: 104)

> result = Strategies::LongTerm::Engine.call(
    instrument: instrument,
    daily_series: daily_series,
    weekly_series: weekly_series
  )

> puts "Signal: #{result[:signal]}"
> puts "Details: #{result.inspect}"
```

**Verification:**
- Similar to swing strategy
- Should use longer timeframes and different criteria

---

## ✅ Phase 5: Backtesting (After Sufficient Data)

### 5.1 Run Small Backtest First

**Why:** Verify backtesting framework works before running large backtests.

```bash
# Run swing backtest for last 30 days (small test)
rails backtest:swing[2024-11-01,2024-12-01,100000]

# Check results
rails backtest:list
rails backtest:show[1]  # Use the run_id from list
```

**Verification:**
- Backtest should complete without errors
- Should generate trades (may be 0 if no signals)
- Results should include P&L, win rate, etc.

### 5.2 Run Comprehensive Backtest

```bash
# Run swing backtest for 3+ months
rails backtest:swing[2024-01-01,2024-12-31,100000]

# Run long-term backtest
rails backtest:long_term[2024-01-01,2024-12-31,100000]

# Generate reports
rails backtest:report[run_id]
```

**Verification:**
- Review backtest metrics (Sharpe ratio, max drawdown, win rate)
- Validate that signals make sense
- Check that risk management is working (stop losses, position sizing)

---

## ✅ Phase 6: System Health & Monitoring

### 6.1 Run System Verification

```bash
# Complete system check
rails verify:complete

# Risk verification
rails verify:risks

# Production readiness
rails production:ready

# Complete workflow
rails verification:workflow
```

**Verification:**
- All checks should pass or have acceptable warnings
- Review any failed checks and fix issues

### 6.2 Check Metrics

```bash
# Daily metrics
rails metrics:daily

# Weekly metrics
rails metrics:weekly

# Job queue status
rails solid_queue:status
```

**Verification:**
- Metrics should show recent activity
- No failed jobs in queue
- System health indicators are green

---

## ✅ Phase 7: Integration Testing

### 7.1 Test End-to-End Workflow

**Why:** Verify the complete flow from screening to signal generation.

```bash
rails console
> # 1. Run screener
> candidates = Screeners::SwingScreener.call(limit: 5)

> # 2. For each candidate, generate signal
> candidates[:candidates].each do |candidate|
>   instrument = Instrument.find_by(symbol_name: candidate[:symbol])
>   next unless instrument
>
>   daily = instrument.load_daily_candles(limit: 200)
>   weekly = instrument.load_weekly_candles(limit: 52)
>
>   signal = Strategies::Swing::Engine.call(
>     instrument: instrument,
>     daily_series: daily,
>     weekly_series: weekly
>   )
>
>   puts "#{candidate[:symbol]}: #{signal[:signal]} (confidence: #{signal[:confidence]})"
> end
```

**Verification:**
- Complete flow should work without errors
- Signals should be generated for candidates
- All components should integrate smoothly

---

## ✅ Phase 8: Data Quality Checks

### 8.1 Verify Candle Data Quality

```bash
rails console
> # Check for missing candles
> instruments = Instrument.where(instrument_type: ['EQUITY', 'INDEX']).limit(10)
> instruments.each do |inst|
>   daily = inst.load_daily_candles(limit: 100)
>   puts "#{inst.symbol_name}: #{daily&.candles&.count || 0} daily candles"
>
>   # Check for gaps
>   if daily && daily.candles.count > 1
>     dates = daily.candles.map(&:time).sort
>     gaps = dates.each_cons(2).select { |a, b| (b - a).to_i > 1 }
>     puts "  Gaps: #{gaps.count}" if gaps.any?
>   end
> end
```

**Verification:**
- Instruments should have sufficient candles (50+ for daily, 10+ for weekly)
- No large gaps in data (except weekends/holidays)
- Data should be recent (within last few days)

### 8.2 Verify Universe Coverage

```bash
rails console
> # Check how many universe symbols have instruments
> universe_symbols = IndexConstituent.distinct.pluck(:symbol).map(&:upcase)
> instruments = Instrument.where(symbol_name: universe_symbols)
>
> puts "Universe symbols: #{universe_symbols.count}"
> puts "Matched instruments: #{instruments.count}"
> puts "Coverage: #{(instruments.count.to_f / universe_symbols.count * 100).round(1)}%"
>
> # Check which symbols are missing
> missing = universe_symbols - instruments.pluck(:symbol_name).map(&:upcase)
> puts "Missing symbols: #{missing.first(10).join(', ')}" if missing.any?
```

**Verification:**
- Coverage should be > 90%
- Missing symbols should be investigated (may be delisted or renamed)

---

## 📋 Quick Reference: Testing Order

1. **Data Ingestion** (30-60 min)
   - Daily candles: `rails runner "Candles::DailyIngestor.call(days_back: 365)"`
   - Weekly candles: `rails runner "Candles::WeeklyIngestor.call(weeks_back: 52)"`

2. **Indicators** (5 min)
   - `rails indicators:test`

3. **Screeners** (5 min)
   - `rails screener:swing`
   - `rails screener:longterm`

4. **Strategy Engines** (10 min)
   - Test in Rails console with sample instruments

5. **Backtesting** (30+ min)
   - Start with small backtest, then comprehensive

6. **System Health** (5 min)
   - `rails verification:workflow`

7. **Integration** (10 min)
   - Test end-to-end workflow

8. **Data Quality** (10 min)
   - Verify candle data and universe coverage

---

## 🚨 Common Issues & Solutions

### Issue: "No candles found for instrument"
**Solution:** Run candle ingestion first (Phase 1)

### Issue: "Indicator calculation failed"
**Solution:** Ensure sufficient candle data (50+ candles minimum)

### Issue: "Screener returns no candidates"
**Solution:** This is normal if market conditions don't meet criteria. Try different instruments or adjust screening parameters.

### Issue: "Backtest has no trades"
**Solution:** Check that:
- Candle data exists for the date range
- Strategy criteria are not too strict
- Instruments in universe have sufficient history

### Issue: "Universe coverage < 90%"
**Solution:**
- Check if symbols were renamed or delisted
- Verify instrument import completed successfully
- Check symbol matching logic (case sensitivity, suffixes)

---

## 🎯 Next Steps After All Tests Pass

1. **Run comprehensive backtest** (3+ months of data)
2. **Review backtest results** and validate strategy performance
3. **Adjust strategy parameters** if needed (in `config/algo.yml`)
4. **Set up automated jobs** (daily candle ingestion, screening)
5. **Enable dry-run mode** for first 30 trades
6. **Monitor system** for a week before going live

---

## 📚 Related Documentation

- [Getting Started Guide](GETTING_STARTED.md)
- [System Overview](SYSTEM_OVERVIEW.md)
- [Backtesting Guide](docs/BACKTESTING_GUIDE.md)
- [Strategy Configuration](docs/STRATEGY_CONFIG.md)

