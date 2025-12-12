# frozen_string_literal: true

# Helper methods for backtest tasks
module BacktestHelpers
  unless respond_to?(:format_comparison_row)
    def self.format_comparison_row(metric, value1, value2)
      "  #{metric.ljust(25)} | Run 1: #{value1.rjust(15)} | Run 2: #{value2.rjust(15)}"
    end
  end

  unless respond_to?(:determine_winner)
    def self.determine_winner(run1, run2)
      # Compare multiple metrics
      score1 = 0
      score2 = 0

      # Total return
      score1 += 1 if run1.total_return > run2.total_return
      score2 += 1 if run2.total_return > run1.total_return

      # Sharpe ratio
      score1 += 1 if run1.sharpe_ratio > run2.sharpe_ratio
      score2 += 1 if run2.sharpe_ratio > run1.sharpe_ratio

      # Win rate
      score1 += 1 if run1.win_rate > run2.win_rate
      score2 += 1 if run2.win_rate > run1.win_rate

      # Profit factor
      score1 += 1 if run1.profit_factor > run2.profit_factor
      score2 += 1 if run2.profit_factor > run1.profit_factor

      # Max drawdown (lower is better)
      score1 += 1 if run1.max_drawdown < run2.max_drawdown
      score2 += 1 if run2.max_drawdown < run1.max_drawdown

      if score1 > score2
        "Run 1 (ID: #{run1.id})"
      elsif score2 > score1
        "Run 2 (ID: #{run2.id})"
      else
        "Tie (both runs perform similarly)"
      end
    end
  end
end

namespace :backtest do
  desc "Run swing trading backtest [from_date] [to_date] [initial_capital]"
  task :swing, %i[from_date to_date initial_capital] => :environment do |_t, args|
    from_date = args[:from_date] ? Date.parse(args[:from_date]) : 3.months.ago.to_date
    to_date = args[:to_date] ? Date.parse(args[:to_date]) : Time.zone.today
    initial_capital = args[:initial_capital]&.to_f || 100_000

    puts "🔬 Running Swing Trading Backtest"
    puts "   Period: #{from_date} to #{to_date}"
    puts "   Initial Capital: ₹#{initial_capital}"
    puts ""

    # Load instruments (use universe or all equity/index)
    instruments = Instrument.where(instrument_type: %w[EQUITY INDEX]).limit(50)

    if instruments.empty?
      puts "❌ No instruments found. Run 'rails instruments:import' first."
      exit 1
    end

    puts "📊 Testing with #{instruments.size} instruments..."
    puts ""

    # Get trailing stop config (optional)
    swing_config = AlgoConfig.fetch(:swing_trading) || {}
    exit_config = swing_config.dig(:strategy, :exit_conditions) || {}
    trailing_stop_pct = exit_config[:trailing_stop_pct]

    # Get commission and slippage config (optional, defaults to 0)
    backtest_config = AlgoConfig.fetch(:backtesting) || {}
    commission_rate = backtest_config[:commission_rate] || 0.0
    slippage_pct = backtest_config[:slippage_pct] || 0.0

    # Run backtest
    result = Backtesting::SwingBacktester.call(
      instruments: instruments,
      from_date: from_date,
      to_date: to_date,
      initial_capital: initial_capital,
      risk_per_trade: 2.0,
      trailing_stop_pct: trailing_stop_pct,
      commission_rate: commission_rate,
      slippage_pct: slippage_pct,
    )

    unless result[:success]
      puts "❌ Backtest failed: #{result[:error]}"
      exit 1
    end

    # Display results
    results = result[:results]
    puts "=" * 60
    puts "📈 BACKTEST RESULTS"
    puts "=" * 60
    puts ""
    puts "💰 Total Return: #{results[:total_return]}%"
    puts "📊 Annualized Return: #{results[:annualized_return].round(2)}%"
    puts "📉 Max Drawdown: #{results[:max_drawdown]}%"
    puts "📈 Sharpe Ratio: #{results[:sharpe_ratio]}"
    puts "📊 Sortino Ratio: #{results[:sortino_ratio]}"
    puts ""
    puts "🎯 Win Rate: #{results[:win_rate]}%"
    puts "📊 Total Trades: #{results[:total_trades]}"
    puts "✅ Winning Trades: #{results[:winning_trades]}"
    puts "❌ Losing Trades: #{results[:losing_trades]}"
    puts "📈 Profit Factor: #{results[:profit_factor]}"
    puts "📊 Avg Win/Loss Ratio: #{results[:avg_win_loss_ratio]}"
    puts ""
    puts "💰 Trading Costs:"
    puts "   Commission: ₹#{results[:total_commission] || 0}"
    puts "   Slippage: ₹#{results[:total_slippage] || 0}"
    puts "   Total: ₹#{results[:total_trading_costs] || 0}"
    puts ""
    puts "⏳ Avg Holding Period: #{results[:avg_holding_period]} days"
    puts "🏆 Best Trade: ₹#{results[:best_trade][:pnl]} (#{results[:best_trade][:pnl_pct]}%)"
    puts "📉 Worst Trade: ₹#{results[:worst_trade][:pnl]} (#{results[:worst_trade][:pnl_pct]}%)"
    puts ""
    puts "📊 Consecutive Wins: #{results[:consecutive_wins]}"
    puts "📉 Consecutive Losses: #{results[:consecutive_losses]}"
    puts ""
    puts "💰 Final Capital: ₹#{result[:portfolio].current_equity.round(2)}"
    puts "=" * 60

    # Save to database
    backtest_run = BacktestRun.create!(
      start_date: from_date,
      end_date: to_date,
      strategy_type: "swing",
      initial_capital: initial_capital,
      risk_per_trade: 2.0,
      total_return: results[:total_return],
      annualized_return: results[:annualized_return],
      max_drawdown: results[:max_drawdown],
      sharpe_ratio: results[:sharpe_ratio],
      win_rate: results[:win_rate],
      total_trades: results[:total_trades],
      status: "completed",
      config: { risk_per_trade: 2.0 }.to_json,
      results: results.to_json,
    )

    # Save positions
    result[:positions].each do |position|
      instrument = Instrument.find_by(id: position.instrument_id)
      next unless instrument

      BacktestPosition.create!(
        backtest_run: backtest_run,
        instrument: instrument,
        entry_date: position.entry_date,
        exit_date: position.exit_date,
        direction: position.direction.to_s,
        entry_price: position.entry_price,
        exit_price: position.exit_price,
        quantity: position.quantity,
        stop_loss: position.stop_loss,
        take_profit: position.take_profit,
        pnl: position.calculate_pnl,
        pnl_pct: position.calculate_pnl_pct,
        holding_days: position.holding_days,
        exit_reason: position.exit_reason,
      )
    end

    puts ""
    puts "✅ Backtest saved to database (Run ID: #{backtest_run.id})"
  end

  desc "Run long-term trading backtest [from_date] [to_date] [initial_capital]"
  task :long_term, %i[from_date to_date initial_capital] => :environment do |_t, args|
    from_date = args[:from_date] ? Date.parse(args[:from_date]) : 6.months.ago.to_date
    to_date = args[:to_date] ? Date.parse(args[:to_date]) : Time.zone.today
    initial_capital = args[:initial_capital]&.to_f || 100_000

    puts "🔬 Running Long-Term Trading Backtest"
    puts "   Period: #{from_date} to #{to_date}"
    puts "   Initial Capital: ₹#{initial_capital}"
    puts ""

    # Load instruments (use universe or all equity/index)
    instruments = Instrument.where(instrument_type: %w[EQUITY INDEX]).limit(50)

    if instruments.empty?
      puts "❌ No instruments found. Run 'rails instruments:import' first."
      exit 1
    end

    puts "📊 Testing with #{instruments.size} instruments..."
    puts ""

    # Get long-term trading config
    long_term_config = AlgoConfig.fetch(:long_term_trading) || {}
    rebalance_frequency = (long_term_config[:rebalance_frequency] || "weekly").to_sym
    max_positions = long_term_config[:max_positions] || 10
    min_holding_days = long_term_config[:holding_period_days] || 30

    # Get commission and slippage config (optional, defaults to 0)
    backtest_config = AlgoConfig.fetch(:backtesting) || {}
    commission_rate = backtest_config[:commission_rate] || 0.0
    slippage_pct = backtest_config[:slippage_pct] || 0.0

    puts "⚙️  Configuration:"
    puts "   Rebalance Frequency: #{rebalance_frequency}"
    puts "   Max Positions: #{max_positions}"
    puts "   Min Holding Days: #{min_holding_days}"
    puts ""

    # Run backtest
    result = Backtesting::LongTermBacktester.call(
      instruments: instruments,
      from_date: from_date,
      to_date: to_date,
      initial_capital: initial_capital,
      risk_per_trade: 2.0,
      rebalance_frequency: rebalance_frequency,
      max_positions: max_positions,
      min_holding_days: min_holding_days,
      commission_rate: commission_rate,
      slippage_pct: slippage_pct,
    )

    unless result[:success]
      puts "❌ Backtest failed: #{result[:error]}"
      exit 1
    end

    # Display results
    results = result[:results]
    puts "=" * 60
    puts "📈 BACKTEST RESULTS (LONG-TERM)"
    puts "=" * 60
    puts ""
    puts "💰 Total Return: #{results[:total_return]}%"
    puts "📊 Annualized Return: #{results[:annualized_return].round(2)}%"
    puts "📉 Max Drawdown: #{results[:max_drawdown]}%"
    puts "📈 Sharpe Ratio: #{results[:sharpe_ratio]}"
    puts "📊 Sortino Ratio: #{results[:sortino_ratio]}"
    puts ""
    puts "🎯 Win Rate: #{results[:win_rate]}%"
    puts "📊 Total Trades: #{results[:total_trades]}"
    puts "✅ Winning Trades: #{results[:winning_trades]}"
    puts "❌ Losing Trades: #{results[:losing_trades]}"
    puts "📈 Profit Factor: #{results[:profit_factor]}"
    puts "📊 Avg Win/Loss Ratio: #{results[:avg_win_loss_ratio]}"
    puts ""
    puts "💰 Trading Costs:"
    puts "   Commission: ₹#{results[:total_commission] || 0}"
    puts "   Slippage: ₹#{results[:total_slippage] || 0}"
    puts "   Total: ₹#{results[:total_trading_costs] || 0}"
    puts ""
    puts "📊 Portfolio Metrics:"
    puts "   Rebalance Count: #{results[:rebalance_count] || 0}"
    puts "   Avg Positions per Rebalance: #{results[:avg_positions_per_rebalance] || 0}"
    puts ""
    puts "⏳ Avg Holding Period: #{results[:avg_holding_period]} days"
    puts "🏆 Best Trade: ₹#{results[:best_trade][:pnl]} (#{results[:best_trade][:pnl_pct]}%)"
    puts "📉 Worst Trade: ₹#{results[:worst_trade][:pnl]} (#{results[:worst_trade][:pnl_pct]}%)"
    puts ""
    puts "📊 Consecutive Wins: #{results[:consecutive_wins]}"
    puts "📉 Consecutive Losses: #{results[:consecutive_losses]}"
    puts ""
    puts "💰 Final Capital: ₹#{result[:portfolio].current_equity.round(2)}"
    puts "=" * 60

    # Save to database
    backtest_run = BacktestRun.create!(
      start_date: from_date,
      end_date: to_date,
      strategy_type: "long_term",
      initial_capital: initial_capital,
      risk_per_trade: 2.0,
      total_return: results[:total_return],
      annualized_return: results[:annualized_return],
      max_drawdown: results[:max_drawdown],
      sharpe_ratio: results[:sharpe_ratio],
      win_rate: results[:win_rate],
      total_trades: results[:total_trades],
      status: "completed",
      config: {
        risk_per_trade: 2.0,
        rebalance_frequency: rebalance_frequency,
        max_positions: max_positions,
        min_holding_days: min_holding_days,
      }.to_json,
      results: results.to_json,
    )

    # Save positions
    result[:positions].each do |position|
      instrument = Instrument.find_by(id: position.instrument_id)
      next unless instrument

      BacktestPosition.create!(
        backtest_run: backtest_run,
        instrument: instrument,
        entry_date: position.entry_date,
        exit_date: position.exit_date,
        direction: position.direction.to_s,
        entry_price: position.entry_price,
        exit_price: position.exit_price,
        quantity: position.quantity,
        stop_loss: position.stop_loss,
        take_profit: position.take_profit,
        pnl: position.calculate_pnl,
        pnl_pct: position.calculate_pnl_pct,
        holding_days: position.holding_days,
        exit_reason: position.exit_reason,
      )
    end

    puts ""
    puts "✅ Backtest saved to database (Run ID: #{backtest_run.id})"
  end

  desc "List all backtest runs"
  task list: :environment do
    runs = BacktestRun.order(created_at: :desc).limit(10)

    if runs.empty?
      puts "No backtest runs found."
      exit 0
    end

    puts "📊 Recent Backtest Runs:"
    puts "=" * 80
    runs.each do |run|
      puts "ID: #{run.id} | #{run.strategy_type.upcase} | #{run.start_date} to #{run.end_date}"
      puts "   Return: #{run.total_return}% | Trades: #{run.total_trades} | Win Rate: #{run.win_rate}%"
      puts "   Status: #{run.status} | Created: #{run.created_at.strftime('%Y-%m-%d %H:%M')}"
      puts "-" * 80
    end
  end

  desc "Show backtest run details [run_id]"
  task :show, [:run_id] => :environment do |_t, args|
    run_id = args[:run_id]&.to_i

    unless run_id
      puts "Usage: rails backtest:show[run_id]"
      exit 1
    end

    run = BacktestRun.find_by(id: run_id)
    unless run
      puts "❌ Backtest run #{run_id} not found"
      exit 1
    end

    _results = run.results_hash

    puts "=" * 60
    puts "📊 BACKTEST RUN ##{run.id}"
    puts "=" * 60
    puts "Period: #{run.start_date} to #{run.end_date}"
    puts "Strategy: #{run.strategy_type}"
    puts "Initial Capital: ₹#{run.initial_capital}"
    puts ""
    puts "💰 Total Return: #{run.total_return}%"
    puts "📊 Annualized Return: #{run.annualized_return&.round(2)}%"
    puts "📉 Max Drawdown: #{run.max_drawdown}%"
    puts "📈 Sharpe Ratio: #{run.sharpe_ratio}"
    puts "🎯 Win Rate: #{run.win_rate}%"
    puts "📊 Total Trades: #{run.total_trades}"
    puts "=" * 60

    positions = run.backtest_positions.order(entry_date: :desc).limit(10)
    if positions.any?
      puts ""
      puts "Recent Trades:"
      positions.each do |pos|
        pnl_emoji = pos.pnl.positive? ? "✅" : "❌"
        puts "#{pnl_emoji} #{pos.instrument.symbol_name}: ₹#{pos.pnl.round(2)} (#{pos.pnl_pct.round(2)}%)"
      end
    end
  end

  desc "Generate report for backtest run [run_id]"
  task :report, [:run_id] => :environment do |_t, args|
    run_id = args[:run_id]&.to_i
    unless run_id
      puts "Usage: rails backtest:report[run_id]"
      exit 1
    end

    run = BacktestRun.find_by(id: run_id)
    unless run
      puts "❌ Backtest run #{run_id} not found"
      exit 1
    end

    puts "📊 Generating report for backtest run #{run_id}..."
    puts ""

    report = Backtesting::ReportGenerator.generate(run)

    # Print summary
    puts report[:summary]
    puts ""

    # Print metrics report
    puts report[:metrics_report]

    # Save CSV files
    output_dir = Rails.root.join("tmp/backtest_reports")
    output_dir.mkpath

    trades_file = output_dir.join("backtest_#{run_id}_trades.csv")
    equity_file = output_dir.join("backtest_#{run_id}_equity_curve.csv")

    File.write(trades_file, report[:trades_csv])
    File.write(equity_file, report[:equity_curve_csv])

    puts ""
    puts "✅ CSV files saved:"
    puts "   Trades: #{trades_file}"
    puts "   Equity Curve: #{equity_file}"

    # Save visualization data
    viz_file = output_dir.join("backtest_#{run_id}_visualization.json")
    File.write(viz_file, JSON.pretty_generate(report[:visualization_data]))
    puts "   Visualization: #{viz_file}"
  end

  desc "Export backtest run to files [run_id]"
  task :export, [:run_id] => :environment do |_t, args|
    run_id = args[:run_id]&.to_i
    unless run_id
      puts "Usage: rails backtest:export[run_id]"
      exit 1
    end

    run = BacktestRun.find_by(id: run_id)
    unless run
      puts "❌ Backtest run #{run_id} not found"
      exit 1
    end

    puts "📦 Exporting backtest run #{run_id}..."
    puts ""

    # Generate report (which creates all files)
    report = Backtesting::ReportGenerator.generate(run)

    output_dir = Rails.root.join("tmp/backtest_reports")
    output_dir.mkpath

    # Save all report formats
    trades_file = output_dir.join("backtest_#{run_id}_trades.csv")
    equity_file = output_dir.join("backtest_#{run_id}_equity_curve.csv")
    summary_file = output_dir.join("backtest_#{run_id}_summary.txt")
    metrics_file = output_dir.join("backtest_#{run_id}_metrics.txt")
    viz_file = output_dir.join("backtest_#{run_id}_visualization.json")

    File.write(trades_file, report[:trades_csv])
    File.write(equity_file, report[:equity_curve_csv])
    File.write(summary_file, report[:summary])
    File.write(metrics_file, report[:metrics_report])
    File.write(viz_file, JSON.pretty_generate(report[:visualization_data]))

    puts "✅ Export complete! Files saved to: #{output_dir}"
    puts ""
    puts "   📄 Summary: #{summary_file}"
    puts "   📊 Metrics: #{metrics_file}"
    puts "   📈 Trades CSV: #{trades_file}"
    puts "   📉 Equity Curve CSV: #{equity_file}"
    puts "   📊 Visualization JSON: #{viz_file}"
  end

  desc "List optimization runs"
  task list_optimizations: :environment do
    runs = OptimizationRun.recent.limit(20)

    if runs.empty?
      puts "No optimization runs found."
      exit 0
    end

    puts "\n=== Optimization Runs (Recent 20) ===\n\n"
    puts "ID     Strategy     Metric     Date Range      Combinations Best Score Status  "
    puts "-" * 85

    runs.each do |run|
      best_metrics = run.best_metrics_hash
      best_score = best_metrics[run.optimization_metric.to_sym] || best_metrics[run.optimization_metric] || 0
      date_range = "#{run.start_date} to #{run.end_date}"

      puts format("%-6s %-12s %-10s %-15s %-12s %-10.2f %-8s",
                  run.id,
                  run.strategy_type,
                  run.optimization_metric,
                  date_range,
                  run.total_combinations_tested,
                  best_score,
                  run.status)
    end

    puts "\nTotal optimization runs: #{OptimizationRun.count}"
  end

  desc "Show optimization run details [run_id]"
  task :show_optimization, [:run_id] => :environment do |_t, args|
    run_id = args[:run_id]&.to_i

    unless run_id
      puts "Usage: rails backtest:show_optimization[RUN_ID]"
      exit 1
    end

    run = OptimizationRun.find_by(id: run_id)

    unless run
      puts "Optimization run ##{run_id} not found."
      exit 1
    end

    puts "\n=== Optimization Run ##{run.id} ===\n\n"
    puts "Strategy Type: #{run.strategy_type}"
    puts "Date Range: #{run.start_date} to #{run.end_date}"
    puts "Initial Capital: ₹#{run.initial_capital}"
    puts "Optimization Metric: #{run.optimization_metric}"
    puts "Walk-Forward: #{run.use_walk_forward ? 'Yes' : 'No'}"
    puts "Total Combinations Tested: #{run.total_combinations_tested}"
    puts "Status: #{run.status}"
    puts "Created: #{run.created_at}"
    puts "Updated: #{run.updated_at}"

    puts "\nError: #{run.error_message}" if run.error_message

    best_params = run.best_parameters_hash
    best_metrics = run.best_metrics_hash

    if best_params.any?
      puts "\n--- Best Parameters ---"
      best_params.each do |key, value|
        puts "  #{key}: #{value}"
      end
    end

    if best_metrics.any?
      puts "\n--- Best Metrics ---"
      best_metrics.each do |key, value|
        puts "  #{key}: #{value}"
      end
    end

    sensitivity = run.sensitivity_analysis_hash
    if sensitivity.any?
      puts "\n--- Sensitivity Analysis ---"
      sensitivity.each do |param, data|
        puts "\n  #{param}:"
        if data.is_a?(Hash)
          data.each do |k, v|
            puts "    #{k}: #{v}"
          end
        else
          puts "    #{data}"
        end
      end
    end

    top_results = run.top_n_results(5)
    if top_results.any?
      puts "\n--- Top 5 Parameter Combinations ---"
      top_results.each_with_index do |result, index|
        params = result["parameters"] || result[:parameters] || {}
        score = result["score"] || result[:score] || 0
        puts "\n  #{index + 1}. Score: #{score.round(2)}"
        params.each do |key, value|
          puts "     #{key}: #{value}"
        end
      end
    end
  end

  desc "Compare two backtest runs [run_id1] [run_id2]"
  task :compare, %i[run_id1 run_id2] => :environment do |_t, args|
    run_id1 = args[:run_id1]&.to_i
    run_id2 = args[:run_id2]&.to_i

    unless run_id1 && run_id2
      puts "Usage: rails backtest:compare[run_id1,run_id2]"
      exit 1
    end

    run1 = BacktestRun.find_by(id: run_id1)
    run2 = BacktestRun.find_by(id: run_id2)

    unless run1 && run2
      puts "❌ One or both backtest runs not found"
      puts "   Run 1 (#{run_id1}): #{run1 ? 'Found' : 'Not found'}"
      puts "   Run 2 (#{run_id2}): #{run2 ? 'Found' : 'Not found'}"
      exit 1
    end

    puts "=" * 80
    puts "📊 BACKTEST COMPARISON"
    puts "=" * 80
    puts ""
    puts "Run 1 (ID: #{run_id1}): #{run1.start_date} to #{run1.end_date}"
    puts "Run 2 (ID: #{run_id2}): #{run2.start_date} to #{run2.end_date}"
    puts ""
    puts "=" * 80
    puts "PERFORMANCE METRICS"
    puts "=" * 80
    puts BacktestHelpers.format_comparison_row("Total Return", "#{run1.total_return}%", "#{run2.total_return}%")
    puts BacktestHelpers.format_comparison_row("Annualized Return", "#{run1.annualized_return.round(2)}%",
                                               "#{run2.annualized_return.round(2)}%")
    puts BacktestHelpers.format_comparison_row("Max Drawdown", "#{run1.max_drawdown}%", "#{run2.max_drawdown}%")
    puts BacktestHelpers.format_comparison_row("Sharpe Ratio", run1.sharpe_ratio.round(4).to_s,
                                               run2.sharpe_ratio.round(4).to_s)
    puts BacktestHelpers.format_comparison_row("Sortino Ratio", run1.sortino_ratio.round(4).to_s,
                                               run2.sortino_ratio.round(4).to_s)
    puts ""
    puts "=" * 80
    puts "TRADE STATISTICS"
    puts "=" * 80
    puts BacktestHelpers.format_comparison_row("Total Trades", run1.total_trades.to_s, run2.total_trades.to_s)
    puts BacktestHelpers.format_comparison_row("Win Rate", "#{run1.win_rate.round(2)}%", "#{run2.win_rate.round(2)}%")
    puts BacktestHelpers.format_comparison_row("Profit Factor", run1.profit_factor.round(2).to_s,
                                               run2.profit_factor.round(2).to_s)
    puts BacktestHelpers.format_comparison_row("Initial Capital", "₹#{run1.initial_capital.to_fs(:delimited)}",
                                               "₹#{run2.initial_capital.to_fs(:delimited)}")
    puts BacktestHelpers.format_comparison_row("Final Capital", "₹#{run1.final_capital.to_fs(:delimited)}",
                                               "₹#{run2.final_capital.to_fs(:delimited)}")
    puts ""
    puts "=" * 80

    # Determine winner
    winner = BacktestHelpers.determine_winner(run1, run2)
    puts ""
    puts "🏆 Winner: #{winner}"
    puts "=" * 80
  end
end
