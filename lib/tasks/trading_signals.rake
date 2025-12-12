# frozen_string_literal: true

namespace :trading_signals do
  desc "Simulate all not-executed signals to calculate what-if P&L"
  task simulate_all: :environment do
    puts "Simulating all not-executed signals..."
    result = TradingSignals::Simulator.simulate_all_not_executed

    if result[:success]
      puts "✅ Simulated #{result[:simulated_count]} signals"
    else
      puts "❌ Simulation failed: #{result[:error]}"
    end
  end

  desc "Simulate a specific signal by ID"
  task :simulate, [:signal_id] => :environment do |_t, args|
    signal_id = args[:signal_id]
    unless signal_id
      puts "Usage: rails trading_signals:simulate[signal_id]"
      exit 1
    end

    signal = TradingSignal.find_by(id: signal_id)
    unless signal
      puts "❌ Signal not found: #{signal_id}"
      exit 1
    end

    puts "Simulating signal #{signal_id} (#{signal.symbol} #{signal.direction})..."
    result = signal.simulate!

    if result[:success]
      sim = result[:simulation]
      puts "✅ Simulation complete:"
      puts "   Entry: ₹#{sim[:entry_price]} on #{sim[:entry_date]}"
      puts "   Exit: ₹#{sim[:exit_price]} on #{sim[:exit_date]} (#{sim[:exit_reason]})"
      puts "   P&L: ₹#{sim[:pnl].round(2)} (#{sim[:pnl_pct]}%)"
      puts "   Holding: #{sim[:holding_days]} days"
    else
      puts "❌ Simulation failed: #{result[:error]}"
    end
  end

  desc "Analyze performance of executed vs simulated signals"
  task analyze: :environment do
    puts "Analyzing trading signals performance..."
    result = TradingSignals::PerformanceAnalyzer.analyze

    puts "\n📊 PERFORMANCE ANALYSIS"
    puts "=" * 60

    puts "\n📈 Executed Signals:"
    exec = result[:executed_signals]
    puts "   Total: #{exec[:total]}"
    puts "   Paper Closed: #{exec[:paper_closed_count]}"
    puts "   Paper Total P&L: ₹#{exec[:paper_total_pnl]}"
    puts "   Paper Avg P&L: ₹#{exec[:paper_avg_pnl]}"
    puts "   Paper Win Rate: #{exec[:paper_win_rate]}%"

    puts "\n🎯 Simulated Signals:"
    sim = result[:simulated_signals]
    puts "   Total: #{sim[:total]}"
    puts "   Profitable: #{sim[:profitable_count]}"
    puts "   Loss Making: #{sim[:loss_making_count]}"
    puts "   Win Rate: #{sim[:win_rate]}%"
    puts "   Total P&L: ₹#{sim[:total_pnl]}"
    puts "   Avg P&L: ₹#{sim[:avg_pnl]}"
    puts "   Avg P&L %: #{sim[:total_pnl_pct]}%"
    puts "   SL Hit: #{sim[:sl_hit_count]}"
    puts "   TP Hit: #{sim[:tp_hit_count]}"
    puts "   Avg Holding: #{sim[:avg_holding_days]} days"

    puts "\n❌ Not Executed Signals:"
    not_exec = result[:not_executed_signals]
    puts "   Total: #{not_exec[:total]}"
    puts "   Insufficient Balance: #{not_exec[:insufficient_balance_count]}"
    puts "   Risk Limits: #{not_exec[:risk_limit_exceeded_count]}"
    puts "   Simulated: #{not_exec[:simulated_count]}"
    puts "   Not Simulated: #{not_exec[:not_simulated_count]}"

    if result[:comparison]
      puts "\n⚖️  Comparison (Executed vs Simulated):"
      comp = result[:comparison]
      puts "   Executed: #{comp[:executed_count]} trades, ₹#{comp[:executed_total_pnl]} total"
      puts "   Simulated: #{comp[:simulated_count]} trades, ₹#{comp[:simulated_total_pnl]} total"
      puts "   Opportunity Cost: ₹#{comp[:opportunity_cost]}"
      puts "   Opportunity Cost %: #{comp[:opportunity_cost_pct]}%"
    end

    puts "\n📋 Summary:"
    summary = result[:summary]
    puts "   Total Signals: #{summary[:total_signals]}"
    puts "   Executed: #{summary[:executed_count]} (#{summary[:executed_pct]}%)"
    puts "   Not Executed: #{summary[:not_executed_count]} (#{summary[:not_executed_pct]}%)"
    puts "   Simulated: #{summary[:simulated_count]} (#{summary[:simulated_pct]}% of not executed)"
  end

  desc "List signals that weren't executed due to insufficient balance"
  task list_insufficient_balance: :environment do
    signals = TradingSignal.not_executed.where("execution_reason LIKE ?", "%Insufficient%").recent.limit(20)

    puts "📊 Signals Not Executed Due to Insufficient Balance"
    puts "=" * 60

    if signals.empty?
      puts "No signals found."
    else
      signals.each do |signal|
        puts "\n#{signal.symbol} - #{signal.direction.upcase}"
        puts "  Entry: ₹#{signal.entry_price}, Qty: #{signal.quantity}"
        puts "  Required: ₹#{signal.required_balance.round(2)}"
        puts "  Available: ₹#{signal.available_balance.round(2)}"
        puts "  Shortfall: ₹#{signal.balance_shortfall.round(2)}"
        puts "  Generated: #{signal.signal_generated_at.strftime('%Y-%m-%d %H:%M')}"
        if signal.simulated?
          puts "  ✅ Simulated: ₹#{signal.simulated_pnl.round(2)} (#{signal.simulated_pnl_pct}%)"
        else
          puts "  ⏳ Not simulated yet"
        end
      end
    end
  end
end
