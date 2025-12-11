# Universe Setup Guide

This guide explains how to set up the instrument universe for filtering during import.

## Overview

The universe system allows you to filter which instruments are imported from the DhanHQ master CSV. This is useful for:
- Limiting to specific indices (Nifty 50, Nifty 100, etc.)
- Focusing on specific sectors
- Reducing database size and processing time

## Setup Steps

### Step 1: Create Universe CSV Files

1. Create the CSV directory (if it doesn't exist):
   ```bash
   mkdir -p config/universe/csv
   ```

2. Add CSV files with instrument symbols. Each CSV should have a `Symbol` column:
   ```csv
   Symbol
   NIFTY
   BANKNIFTY
   RELIANCE
   TCS
   ```

   **Example sources:**
   - NSE Index constituents: https://www.niftyindices.com/IndexConstituent/
   - Custom watchlists
   - Manual CSV files

3. **Example: Download Nifty 50 constituents:**
   ```bash
   curl -o config/universe/csv/nifty50.csv \
     "https://www.niftyindices.com/IndexConstituent/ind_nifty50list.csv"
   ```

### Step 2: Build Master Universe

Run the rake task to build the master universe from all CSV files:

```bash
rails universe:build
```

This will:
- Read all CSV files from `config/universe/csv/`
- Extract symbols from the `Symbol` column (or variations like `SYMBOL`, `symbol`, etc.)
- Normalize symbols (uppercase, remove suffixes like `-EQ`, `-BE`)
- Create `config/universe/master_universe.yml` with unique symbols

**Output example:**
```
📊 Building master universe from 2 CSV file(s)...
  Reading: nifty50.csv
  Reading: custom_watchlist.csv

✅ Master universe built successfully!
   Universe size: 75 instruments
   Output file: /path/to/config/universe/master_universe.yml

📋 Sample symbols (first 10):
   - BANKNIFTY
   - BHARTIARTL
   - HDFCBANK
   - ICICIBANK
   - INFY
   - ITC
   - NIFTY
   - RELIANCE
   - SBIN
   - TCS
   ...
```

### Step 3: Verify Universe

Check universe statistics:
```bash
rails universe:stats
```

Validate against imported instruments:
```bash
rails universe:validate
```

### Step 4: Import Instruments (with Universe Filtering)

When you run `rails instruments:import`, the importer will:
- Check if `config/universe/master_universe.yml` exists
- If it exists, only import instruments whose symbols match the universe
- If it doesn't exist, import all instruments (no filtering)

**Example:**
```bash
# With universe filtering (if master_universe.yml exists)
rails instruments:import

# Check what was imported
rails instruments:status
```

## Optional: Disable Universe Filtering

If you want to import all instruments regardless of the universe file:

1. **Temporary:** Rename or move `config/universe/master_universe.yml`
2. **Permanent:** Modify `app/services/instruments_importer.rb` to not load the universe

## CSV Format Requirements

The CSV files should have one of these column names for symbols:
- `Symbol` (preferred)
- `SYMBOL`
- `symbol`
- `TradingSymbol`
- `TRADING_SYMBOL`
- `SymbolName`
- `SYMBOL_NAME`

**Example CSV:**
```csv
Symbol,Company Name,Industry
RELIANCE,Reliance Industries Ltd.,Oil & Gas
TCS,Tata Consultancy Services,IT
INFY,Infosys Ltd.,IT
```

The rake task will automatically:
- Extract symbols from any of these columns
- Normalize to uppercase
- Remove suffixes (e.g., `RELIANCE-EQ` → `RELIANCE`)
- Deduplicate across all CSV files

## Troubleshooting

### "Universe CSV directory not found"
Create the directory:
```bash
mkdir -p config/universe/csv
```

### "No CSV files found"
Add at least one CSV file with a `Symbol` column to `config/universe/csv/`

### "No symbols found in CSV files"
Ensure your CSV files have a header row with one of the supported column names (`Symbol`, `SYMBOL`, etc.)

### Universe not being applied during import
- Check that `config/universe/master_universe.yml` exists
- Verify the file is valid YAML: `cat config/universe/master_universe.yml`
- Check importer logs for universe loading messages

## Example Workflow

```bash
# 1. Create directory
mkdir -p config/universe/csv

# 2. Add CSV files (example: download Nifty 50)
curl -o config/universe/csv/nifty50.csv \
  "https://www.niftyindices.com/IndexConstituent/ind_nifty50list.csv"

# 3. Build universe
rails universe:build

# 4. Verify
rails universe:stats

# 5. Import (will use universe filtering)
rails instruments:import

# 6. Validate
rails universe:validate
```

