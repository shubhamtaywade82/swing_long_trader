# frozen_string_literal: true

namespace :backtest do
  desc 'Run swing trading backtest [from_date] [to_date] [initial_capital]'
  task :swing, [:from_date, :to_date, :initial_capital] => :environment do |_t, args|
    from_date = args[:from_date] ? Date.parse(args[:from_date]) : 3.months.ago.to_date
    to_date = args[:to_date] ? Date.parse(args[:to_date]) : Date.today
    initial_capital = args[:initial_capital]&.to_f || 100_000

    puts "🔬 Running Swing Trading Backtest"
    puts "   Period: #{from_date} to #{to_date}"
    puts "   Initial Capital: ₹#{initial_capital}"
    puts ""

    # Load instruments (use universe or all equity/index)
    instruments = Instrument.where(instrument_type: ['EQUITY', 'INDEX']).limit(50)

    if instruments.empty?
      puts "❌ No instruments found. Run 'rails instruments:import' first."
      exit 1
    end

    puts "📊 Testing with #{instruments.size} instruments..."
    puts ""

    # Run backtest
    result = Backtesting::SwingBacktester.call(
      instruments: instruments,
      from_date: from_date,
      to_date: to_date,
      initial_capital: initial_capital,
      risk_per_trade: 2.0
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
      strategy_type: 'swing',
      initial_capital: initial_capital,
      risk_per_trade: 2.0,
      total_return: results[:total_return],
      annualized_return: results[:annualized_return],
      max_drawdown: results[:max_drawdown],
      sharpe_ratio: results[:sharpe_ratio],
      win_rate: results[:win_rate],
      total_trades: results[:total_trades],
      status: 'completed',
      config: { risk_per_trade: 2.0 }.to_json,
      results: results.to_json
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
        exit_reason: position.exit_reason
      )
    end

    puts ""
    puts "✅ Backtest saved to database (Run ID: #{backtest_run.id})"
  end

  desc 'List all backtest runs'
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

  desc 'Show backtest run details [run_id]'
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

    results = run.results_hash

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
        pnl_emoji = pos.pnl.positive? ? '✅' : '❌'
        puts "#{pnl_emoji} #{pos.instrument.symbol_name}: ₹#{pos.pnl.round(2)} (#{pos.pnl_pct.round(2)}%)"
      end
    end
  end
end

