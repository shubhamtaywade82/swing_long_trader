# frozen_string_literal: true

# Rails console testing utilities
# Usage: rails runner script/test_console.rb [command] [args...]

require_relative "../config/environment"

class TestConsole
  def self.run(command, *args)
    new.send(command.to_sym, *args)
  rescue NoMethodError
    puts "❌ Unknown command: #{command}"
    puts "Available commands: mtf_analyzer, mtf_screener, mtf_signal, capital_portfolio, position_size"
  end

  def mtf_analyzer(symbol = "RELIANCE")
    puts "\n🔍 Multi-Timeframe Analyzer Test: #{symbol}\n"
    instrument = Instrument.find_by(symbol_name: symbol.upcase)
    return puts "❌ Instrument not found" unless instrument

    result = Swing::MultiTimeframeAnalyzer.call(instrument: instrument, include_intraday: true)
    if result[:success]
      analysis = result[:analysis]
      puts "✅ MTF Score: #{analysis[:multi_timeframe_score]}/100"
      puts "✅ Trend Aligned: #{analysis[:trend_alignment][:aligned]}"
      puts "✅ Momentum Aligned: #{analysis[:momentum_alignment][:aligned]}"
      analysis[:timeframes].each do |tf, data|
        puts "   #{tf}: Trend #{data[:trend_score]}/100, Momentum #{data[:momentum_score]}/100"
      end
    else
      puts "❌ Failed: #{result[:error]}"
    end
  end

  def mtf_screener(limit = 5)
    puts "\n🔍 Multi-Timeframe Screener Test (Top #{limit})\n"
    candidates = Screeners::SwingScreener.call(limit: limit.to_i)
    candidates.each_with_index do |c, idx|
      puts "#{idx + 1}. #{c[:symbol]}: Score #{c[:score]}/100 (MTF: #{c[:mtf_score]}/100)"
    end
  end

  def mtf_signal(symbol = "RELIANCE")
    puts "\n🔍 Signal Builder Test: #{symbol}\n"
    instrument = Instrument.find_by(symbol_name: symbol.upcase)
    return puts "❌ Instrument not found" unless instrument

    daily_series = instrument.load_daily_candles(limit: 100)
    weekly_series = instrument.load_weekly_candles(limit: 52)

    signal = Strategies::Swing::SignalBuilder.call(
      instrument: instrument,
      daily_series: daily_series,
      weekly_series: weekly_series,
    )

    if signal
      puts "✅ Entry: ₹#{signal[:entry_price]}, SL: ₹#{signal[:sl]}, TP: ₹#{signal[:tp]}"
      puts "✅ Confidence: #{signal[:confidence]}/100"
      puts "✅ RR: #{signal[:rr]}:1"
    else
      puts "❌ Signal generation failed"
    end
  end

  def capital_portfolio(name = "Test Portfolio", equity = 500_000)
    puts "\n💰 Capital Allocation Portfolio Test\n"
    portfolio = CapitalAllocationPortfolio.find_or_create_by(name: name) do |p|
      p.mode = "paper"
      p.total_equity = equity.to_f
      p.available_cash = equity.to_f
      p.swing_capital = 0
      p.long_term_capital = 0
      p.peak_equity = equity.to_f
    end

    PortfolioServices::CapitalBucketer.new(portfolio: portfolio).call
    portfolio.reload

    puts "✅ Portfolio: #{portfolio.name}"
    puts "   Equity: ₹#{portfolio.total_equity.round(2)}"
    puts "   Swing: ₹#{portfolio.swing_capital.round(2)}"
    puts "   Long-Term: ₹#{portfolio.long_term_capital.round(2)}"
    puts "   Cash: ₹#{portfolio.available_cash.round(2)}"
  end

  def position_size(symbol = "RELIANCE", entry = 2500, sl = 2400)
    puts "\n📏 Position Sizing Test: #{symbol}\n"
    portfolio = CapitalAllocationPortfolio.find_or_create_by(name: "Test Portfolio") do |p|
      p.mode = "paper"
      p.total_equity = 500_000
      p.available_cash = 500_000
      p.swing_capital = 400_000
      p.long_term_capital = 0
      p.peak_equity = 500_000
    end

    PortfolioServices::CapitalBucketer.new(portfolio: portfolio).call

    instrument = Instrument.find_by(symbol_name: symbol.upcase)
    return puts "❌ Instrument not found" unless instrument

    result = Swing::PositionSizer.call(
      portfolio: portfolio,
      entry_price: entry.to_f,
      stop_loss: sl.to_f,
      instrument: instrument,
    )

    if result[:success]
      puts "✅ Quantity: #{result[:quantity]} shares"
      puts "✅ Capital: ₹#{result[:capital_required].round(2)}"
      puts "✅ Risk: ₹#{result[:risk_amount].round(2)} (#{result[:risk_percentage]}%)"
    else
      puts "❌ Failed: #{result[:error]}"
    end
  end

  def ai_eval(symbol = "RELIANCE")
    puts "\n🤖 AI Evaluator Test: #{symbol}\n"
    instrument = Instrument.find_by(symbol_name: symbol.upcase)
    return puts "❌ Instrument not found" unless instrument

    # Generate signal first
    daily_series = instrument.load_daily_candles(limit: 100)
    weekly_series = instrument.load_weekly_candles(limit: 52)

    signal = Strategies::Swing::SignalBuilder.call(
      instrument: instrument,
      daily_series: daily_series,
      weekly_series: weekly_series,
    )

    unless signal
      puts "❌ Failed to generate signal"
      return
    end

    puts "📊 Signal: Entry ₹#{signal[:entry_price]}, SL ₹#{signal[:sl]}, TP ₹#{signal[:tp]}"
    puts "🤖 Calling AI Evaluator...\n"

    result = Strategies::Swing::AIEvaluator.call(signal)

    if result[:success]
      puts "✅ AI Score: #{result[:ai_score]}/100"
      puts "✅ AI Confidence: #{result[:ai_confidence]}/100"
      puts "✅ Timeframe Alignment: #{result[:timeframe_alignment]&.upcase || 'N/A'}"
      puts "✅ Entry Timing: #{result[:entry_timing]&.upcase || 'N/A'}"
      puts "✅ Risk: #{result[:ai_risk]&.upcase || 'N/A'}"
      puts "\n📝 Summary: #{result[:ai_summary]}"
      puts "💾 Cached: #{result[:cached] ? 'Yes' : 'No'}"
    else
      puts "❌ Failed: #{result[:error]}"
    end
  end
end

# Run command if executed directly
if __FILE__ == $PROGRAM_NAME
  command = ARGV[0] || "mtf_analyzer"
  TestConsole.run(command, *ARGV[1..])
end
