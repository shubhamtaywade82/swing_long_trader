# 📊 Universe Index Selection Guide

**Recommended NSE indices for Swing + Long-Term Trading**

---

## 🎯 Selection Criteria

Based on your trading strategy requirements:
- **Minimum Volume**: 1,000,000 daily
- **Minimum Price**: ₹50
- **Exclude Penny Stocks**: Yes
- **Minimum Market Cap**: 1,000 crores (optional filter)
- **Focus**: Quality stocks with good liquidity

---

## ✅ Recommended Indices

### Core Large Cap (High Liquidity, Stable)
1. **Nifty 50** - Top 50 largest companies, highest liquidity
2. **Nifty Next 50** - Next 50 large caps, emerging leaders
3. **Nifty 100** - Combines Nifty 50 + Next 50
4. **Nifty 200** - Top 200 (large + mid cap mix)
5. **Nifty 500** - Broadest quality coverage (top 500 companies)

**Why**: These provide the most liquid, stable stocks perfect for swing trading and long-term positions.

### Mid Cap (Growth Potential)
6. **Nifty Midcap 150** - Comprehensive mid cap coverage
7. **Nifty Midcap 100** - Top mid caps (subset of Midcap 150)

**Why**: Mid caps offer good growth potential with reasonable liquidity for swing trading.

### Small Cap (Selective Quality)
8. **Nifty Smallcap 250** - Quality small caps with decent liquidity
9. **Nifty Smallcap 100** - Top small caps (subset of Smallcap 250)

**Why**: Quality small caps can provide swing trading opportunities, but we're selective to avoid penny stocks.

### Sector Indices (Diversification)
10. **Nifty Bank** - Banking sector
11. **Nifty IT** - Information Technology
12. **Nifty FMCG** - Fast Moving Consumer Goods
13. **Nifty Pharma** - Pharmaceuticals
14. **Nifty Auto** - Automotive

**Why**: Sector indices ensure diversification and capture sector-specific opportunities.

---

## ❌ Excluded Indices

### Too Risky / Low Quality
- **Nifty Microcap 250** - Too risky, includes penny stocks, low liquidity
- **Nifty Total Market** - Too broad, includes everything (even very small companies)

### Redundant (Already Covered)
- **Nifty500 Multicap 50:25:25** - Already covered by Nifty 500
- **Nifty500 LargeMidSmall Equal-Cap** - Already covered by Nifty 500
- **Nifty MidSmallcap 400** - Already covered by Midcap 150 + Smallcap 250
- **Nifty LargeMidcap 250** - Already covered by Nifty 200/500
- **Nifty Midcap 50** - Already covered by Midcap 150
- **Nifty Midcap Select** - Already covered by Midcap 150
- **Nifty Smallcap 50** - Already covered by Smallcap 250

---

## 📈 Expected Universe Size

With the recommended indices, you should get:
- **~800-1,200 unique stocks** after deduplication
- **Mix**: ~50% large cap, ~30% mid cap, ~20% small cap
- **All stocks**: Meet minimum volume, price, and market cap criteria

---

## 🔄 How It Works

1. **Download**: `rails universe:build` downloads all index CSVs
2. **Extract**: Symbols and ISINs are extracted from each CSV
3. **Deduplicate**: Same symbol appears in multiple indices → kept once
4. **Filter**: During import, instruments are matched by symbol or ISIN
5. **Result**: Clean universe of quality stocks for trading

---

## 🎛️ Customization

If you want to adjust the universe:

### More Conservative (Fewer Stocks)
- Remove: Smallcap 250, Smallcap 100
- Keep: Nifty 50, Next 50, 200, 500, Midcap 150

### More Aggressive (More Stocks)
- Add: Nifty MidSmallcap 400 (if you want more mid/small cap exposure)
- Note: This may include some lower-quality stocks

### Sector Focus
- Add more sector indices based on your strategy
- Examples: Nifty Energy, Nifty Metal, Nifty Realty, etc.

---

## 📝 Notes

- **Deduplication is automatic**: If a stock appears in multiple indices, it's only included once
- **ISIN matching**: Improves accuracy when symbols differ slightly (e.g., "RELIANCE" vs "RELIANCE-EQ")
- **Regular updates**: Run `rails universe:build` monthly to capture index changes
- **Validation**: Use `rails universe:validate` to check universe against imported instruments

