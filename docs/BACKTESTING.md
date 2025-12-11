# Backtesting Framework Documentation

## Overview

The backtesting framework allows you to validate trading strategies using historical data before deploying them in live trading. It simulates trades using past market data and calculates performance metrics to evaluate strategy effectiveness.

## Methodology

### Walk-Forward Approach

The backtesting system uses a **walk-forward** approach to avoid look-ahead bias:

1. **No Future Data**: Only uses data available up to the current date being processed
2. **Sequential Processing**: Processes dates chronologically, one day at a time
3. **Historical Context**: For each date, only candles with timestamps <= current date are used
4. **Signal Generation**: Uses the same `Strategies::Swing::Engine` as live trading

### How It Works

```
For each date from start_date to end_date:
  1. Load all candles up to current date
  2. Check for entry signals using strategy engine
  3. Open positions if signals found
  4. Check exit conditions for open positions
  5. Close positions if exit conditions met
  6. Track P&L and update portfolio
```

### Key Principles

- **No Look-Ahead Bias**: Never uses future data to make past decisions
- **Same Logic**: Uses identical signal generation as live trading
- **Realistic Simulation**: Applies slippage and commissions if configured
- **Position Management**: Tracks open/closed positions and portfolio equity

## Performance Metrics

### Return Metrics

#### Total Return
- **Definition**: Percentage change from initial capital to final capital
- **Formula**: `((Final Capital - Initial Capital) / Initial Capital) * 100`
- **Interpretation**: Overall profitability of the strategy

#### Annualized Return
- **Definition**: Total return adjusted to annual rate
- **Formula**: `((Final Capital / Initial Capital)^(1/years) - 1) * 100`
- **Interpretation**: Expected yearly return if strategy continues

### Risk Metrics

#### Maximum Drawdown
- **Definition**: Largest peak-to-trough decline in portfolio value
- **Calculation**: Tracks equity curve and finds maximum decline
- **Interpretation**: Worst-case loss from a peak
- **Lower is better**

#### Sharpe Ratio
- **Definition**: Risk-adjusted return measure
- **Formula**: `(Average Return - Risk-Free Rate) / Standard Deviation of Returns * sqrt(252)`
- **Interpretation**:
  - > 1: Good
  - > 2: Very good
  - > 3: Excellent
- **Higher is better**

#### Sortino Ratio
- **Definition**: Similar to Sharpe but only penalizes downside volatility
- **Formula**: `(Average Return - Risk-Free Rate) / Downside Deviation * sqrt(252)`
- **Interpretation**: Better measure for strategies with asymmetric returns
- **Higher is better**

### Trade Statistics

#### Win Rate
- **Definition**: Percentage of profitable trades
- **Formula**: `(Winning Trades / Total Trades) * 100`
- **Interpretation**:
  - > 50%: Good
  - > 60%: Very good
  - Note: High win rate doesn't guarantee profitability

#### Profit Factor
- **Definition**: Ratio of gross profit to gross loss
- **Formula**: `Total Gross Profit / Total Gross Loss`
- **Interpretation**:
  - > 1: Profitable
  - > 1.5: Good
  - > 2: Excellent
- **Higher is better**

#### Average Win/Loss Ratio
- **Definition**: Average winning trade size vs average losing trade size
- **Formula**: `Average Win / Average Loss`
- **Interpretation**:
  - > 1: Wins are larger than losses
  - > 2: Strong risk management
- **Higher is better**

#### Consecutive Wins/Losses
- **Definition**: Maximum number of consecutive winning/losing trades
- **Interpretation**:
  - High consecutive losses: May indicate strategy breakdown
  - High consecutive wins: May indicate overfitting or luck

## How to Run Backtests

### Basic Swing Trading Backtest

```bash
# Run backtest for a date range
rails backtest:swing[2024-01-01,2024-12-31,100000]

# Parameters:
# - from_date: Start date (YYYY-MM-DD)
# - to_date: End date (YYYY-MM-DD)
# - initial_capital: Starting capital (default: 100000)
```

### View Results

```bash
# List all backtest runs
rails backtest:list

# Show details of a specific run
rails backtest:show[1]

# Generate comprehensive report
rails backtest:report[1]

# Export all files
rails backtest:export[1]
```

### Compare Backtests

```bash
# Compare two backtest runs
rails backtest:compare[1,2]
```

## Interpreting Results

### Good Strategy Indicators

1. **Positive Total Return**: Strategy is profitable
2. **Sharpe Ratio > 1**: Good risk-adjusted returns
3. **Win Rate > 50%**: More wins than losses
4. **Profit Factor > 1.5**: Strong profit generation
5. **Max Drawdown < 20%**: Acceptable risk level
6. **Consistent Performance**: Similar results across different periods

### Warning Signs

1. **High Max Drawdown (>30%)**: Excessive risk
2. **Low Sharpe Ratio (<0.5)**: Poor risk-adjusted returns
3. **Low Win Rate (<40%)**: Strategy may not be working
4. **Profit Factor < 1**: Losing strategy
5. **High Consecutive Losses**: Strategy may have broken down

### Red Flags

1. **Negative Total Return**: Strategy loses money
2. **Extreme Drawdowns**: Risk of account blowup
3. **Inconsistent Results**: May indicate overfitting
4. **All Losses**: Strategy completely ineffective

## Limitations and Assumptions

### Limitations

1. **Historical Data Quality**: Results depend on data accuracy
2. **Slippage**: Real trading has slippage (can be simulated)
3. **Market Impact**: Large orders may move prices (not simulated)
4. **Liquidity**: Assumes all orders can be filled at close price
5. **Gaps**: Doesn't account for overnight gaps
6. **Market Conditions**: Past performance doesn't guarantee future results

### Assumptions

1. **Perfect Execution**: Orders filled at exact entry/exit prices
2. **No Slippage**: Default assumes no slippage (can be configured)
3. **No Commissions**: Default assumes no commissions (can be configured)
4. **Sufficient Liquidity**: All positions can be opened/closed
5. **No Partial Fills**: Full position size always executed
6. **Market Hours**: Only considers trading days

### Important Notes

- **Backtest Results ≠ Live Results**: Real trading has additional factors
- **Overfitting Risk**: Optimizing too much can lead to poor live performance
- **Market Regime Changes**: Strategies may work in some markets but not others
- **Sample Size**: Need sufficient trades for statistical significance
- **Out-of-Sample Testing**: Always validate on unseen data

## Best Practices

### 1. Use Sufficient Data
- Minimum 3-6 months for swing trading
- Include different market conditions (bull, bear, sideways)

### 2. Avoid Overfitting
- Don't optimize parameters too aggressively
- Use out-of-sample validation
- Test on multiple time periods

### 3. Realistic Assumptions
- Include slippage (0.1-0.5% for stocks)
- Include commissions if applicable
- Consider market impact for large positions

### 4. Multiple Scenarios
- Test in different market conditions
- Test with different initial capital
- Test with different risk per trade

### 5. Validate Results
- Compare backtest vs live (when available)
- Monitor for strategy degradation
- Review metrics regularly

## Configuration

### Backtest Parameters

Backtests can be configured using `Backtesting::Config`:

```ruby
config = Backtesting::Config.new(
  initial_capital: 100_000,
  risk_per_trade: 2.0,  # 2% risk per trade
  commission_rate: 0.0,  # 0% commission
  slippage_pct: 0.1,     # 0.1% slippage
  position_sizing_method: :risk_based
)
```

### Strategy Overrides

You can override strategy parameters for testing:

```ruby
config = Backtesting::Config.new(
  strategy_overrides: {
    min_confidence: 0.8,
    min_risk_reward: 2.0
  }
)
```

## Report Formats

### Summary Report
- High-level overview
- Key performance metrics
- Trade statistics

### Metrics Report
- Detailed performance breakdown
- Monthly returns
- Trade distribution analysis

### CSV Exports
- **Trades CSV**: All individual trades with P&L
- **Equity Curve CSV**: Portfolio value over time

### Visualization JSON
- Equity curve data
- Monthly returns
- Trade distribution
- Ready for charting libraries

## Troubleshooting

### No Trades Generated

**Possible Causes:**
- Insufficient historical data
- Strategy filters too strict
- Date range too short
- No instruments meet criteria

**Solutions:**
- Check data availability: `rails candles:status`
- Review strategy parameters in `config/algo.yml`
- Extend date range
- Check instrument universe

### Unrealistic Results

**Possible Causes:**
- Look-ahead bias (shouldn't happen with walk-forward)
- Data quality issues
- Overfitting

**Solutions:**
- Verify walk-forward logic
- Check data for gaps or errors
- Test on out-of-sample data
- Review strategy logic

### High Drawdowns

**Possible Causes:**
- Strategy not working
- Market conditions changed
- Over-leveraged positions

**Solutions:**
- Review entry/exit logic
- Test in different market conditions
- Reduce position sizes
- Add additional filters

## Advanced Features

### Walk-Forward Analysis (Coming Soon)
- In-sample/out-of-sample validation
- Rolling window backtesting
- Expanding window backtesting

### Parameter Optimization (Optional)
- Grid search for optimal parameters
- Genetic algorithm optimization
- Sensitivity analysis

### Monte Carlo Simulation (Optional)
- Trade sequence randomization
- Probability distributions
- Confidence intervals
- Worst-case scenario analysis

## Examples

### Example 1: Basic Backtest

```bash
# Test strategy on last 6 months
rails backtest:swing[2024-06-01,2024-12-31,100000]
```

### Example 2: Compare Strategies

```bash
# Run backtest with different parameters
rails backtest:swing[2024-01-01,2024-12-31,100000]

# Compare results
rails backtest:compare[1,2]
```

### Example 3: Generate Report

```bash
# Run backtest
rails backtest:swing[2024-01-01,2024-12-31,100000]

# Generate comprehensive report
rails backtest:report[1]

# Files saved to tmp/backtest_reports/
```

## Additional Resources

- [Architecture Documentation](architecture.md)
- [Runbook](runbook.md)
- [Production Checklist](PRODUCTION_CHECKLIST.md)

