# ⚡ SwingLongTrader Importer Quick Reference

**Quick reference for NSE stocks-only importer setup**

---

## 🎯 Goal

Import **ONLY NSE equity stocks** that appear in **ANY NSE index**, creating a clean universe of ~1,000-1,300 quality stocks for swing/long-term trading.

---

## 📋 Setup Steps (In Order)

### 1. Download NSE Index CSVs

```bash
# Create directory
mkdir -p config/universe/csv

# Download main indices
curl -o config/universe/csv/nifty50.csv "https://www.niftyindices.com/IndexConstituent/ind_nifty50list.csv"
curl -o config/universe/csv/nifty100.csv "https://www.niftyindices.com/IndexConstituent/ind_nifty100list.csv"
curl -o config/universe/csv/nifty200.csv "https://www.niftyindices.com/IndexConstituent/ind_nifty200list.csv"
curl -o config/universe/csv/nifty500.csv "https://www.niftyindices.com/IndexConstituent/ind_nifty500list.csv"
curl -o config/universe/csv/midcap100.csv "https://www.niftyindices.com/IndexConstituent/ind_niftymidcap100list.csv"
curl -o config/universe/csv/smallcap100.csv "https://www.niftyindices.com/IndexConstituent/ind_niftysmallcap100list.csv"

# Download sector indices (examples)
curl -o config/universe/csv/nifty_bank.csv "https://www.niftyindices.com/IndexConstituent/ind_niftybanklist.csv"
curl -o config/universe/csv/nifty_it.csv "https://www.niftyindices.com/IndexConstituent/ind_niftyitlist.csv"
# ... add more sector indices as needed
```

### 2. Build Master Universe

```bash
rails universe:build
```

**Output:** `config/universe/master_universe.yml` with ~1,000-1,300 unique symbols

### 3. Import Instruments

```bash
rails instruments:import
```

**What it does:**
- Downloads DhanHQ CSV
- Filters to NSE_EQ segment only
- Filters to symbols in master_universe.yml
- Upserts instruments to database

### 4. Verify Import

```bash
# Check status
rails instruments:status

# Check counts
rails runner "puts Instrument.count"  # Should be ~1,000-1,300
rails runner "puts Instrument.where(exchange: 'NSE', segment: 'EQ').count"  # Should match total
rails runner "puts Instrument.where(segment: 'D').count"  # Should be 0 (no derivatives)
```

---

## 🗂️ File Structure

```
swing_long_trader/
├── config/
│   └── universe/
│       ├── csv/
│       │   ├── nifty50.csv
│       │   ├── nifty100.csv
│       │   └── ... (all index CSVs)
│       └── master_universe.yml  # Generated
├── app/
│   ├── models/
│   │   ├── instrument.rb  # Modified (derivatives removed)
│   │   └── watchlist_item.rb  # Modified (derivative enum removed)
│   └── services/
│       └── instruments_importer.rb  # REWRITTEN (stocks-only)
└── lib/
    └── tasks/
        ├── instruments.rake  # Modified (no derivative stats)
        └── universe.rake  # NEW (universe builder)
```

---

## ✅ What Gets Imported

- ✅ NSE exchange only
- ✅ Equity segment (EQ) only
- ✅ Symbols in NSE index constituents
- ✅ ~1,000-1,300 quality stocks

## ❌ What Does NOT Get Imported

- ❌ Derivatives (options, futures)
- ❌ Indices (NIFTY, BANKNIFTY, etc.)
- ❌ BSE stocks
- ❌ Non-index stocks
- ❌ Penny stocks
- ❌ Illiquid stocks
- ❌ SME stocks

---

## 🔧 Key Modifications

### InstrumentsImporter

**Removed:**
- `import_derivatives!` method
- `attach_instrument_ids` method
- Derivative batch building
- Derivative statistics

**Added:**
- Universe whitelist filtering
- Symbol normalization
- NSE_EQ segment filtering

### Instrument Model

**Removed:**
```ruby
has_many :derivatives
accepts_nested_attributes_for :derivatives
```

**Kept:**
```ruby
has_many :watchlist_items
has_many :candle_series
```

### WatchlistItem Model

**Removed:**
```ruby
derivative: 2,  # from enum
def derivative  # method
```

**Kept:**
```ruby
equity: 1,  # from enum
def instrument  # method
```

---

## 📊 Expected Results

| Metric | Value |
|--------|-------|
| Total instruments | ~1,000-1,300 |
| Exchange | All NSE |
| Segment | All EQ |
| Derivatives | 0 |
| Indices | 0 |
| Universe match | 100% |

---

## 🚨 Common Issues

### Issue: "Master universe not found"

**Solution:**
```bash
rails universe:build
```

### Issue: "No symbols in universe"

**Solution:**
- Check CSV files exist in `config/universe/csv/`
- Verify CSV format (should have 'Symbol' column)
- Check CSV download URLs are correct

### Issue: "Import returns 0 instruments"

**Solution:**
- Verify master_universe.yml exists and has symbols
- Check DhanHQ CSV download works
- Verify symbol normalization matches (remove -EQ suffix)

### Issue: "Derivatives still being imported"

**Solution:**
- Check importer filters: `row['SEGMENT'] == 'E' || row['SEGMENT'] == 'EQ'`
- Verify no derivative import method is called
- Check Instrument model has no derivatives association

---

## 📚 Full Documentation

- **Complete Guide**: `docs/SWING_CLEAN_IMPORTER_GUIDE.md`
- **Migration Guide**: `docs/SWING_LONG_TRADER_MIGRATION_GUIDE.md`
- **File Map**: `docs/SWING_MIGRATION_FILE_MAP.md`
- **Checklist**: `docs/SWING_MIGRATION_CHECKLIST.md`

---

## 🎯 Next Steps

After successful import:

1. ✅ Verify instrument count matches universe
2. ✅ Set up candle ingestion (daily/weekly)
3. ✅ Configure screener to use imported instruments
4. ✅ Set up watchlists for swing candidates
5. ✅ Begin screening and AI ranking

---

**Last Updated:** Based on clean importer implementation

