# frozen_string_literal: true

# Console helper methods for testing
# Load in Rails console with: load 'lib/console_helpers.rb'

module ConsoleHelpers
  def mtf_analyze(symbol = "RELIANCE")
    instrument = Instrument.find_by(symbol_name: symbol.upcase)
    return puts "❌ Instrument not found" unless instrument

    result = Swing::MultiTimeframeAnalyzer.call(instrument: instrument, include_intraday: true)
    if result[:success]
      analysis = result[:analysis]
      puts "\n📊 Multi-Timeframe Analysis: #{symbol}"
      puts "=" * 60
      puts "MTF Score: #{analysis[:multi_timeframe_score]}/100"
      puts "Trend Aligned: #{analysis[:trend_alignment][:aligned] ? '✅' : '❌'}"
      puts "Momentum Aligned: #{analysis[:momentum_alignment][:aligned] ? '✅' : '❌'}"
      puts "\nTimeframes:"
      analysis[:timeframes].each do |tf, data|
        puts "  #{tf.to_s.upcase}: Trend #{data[:trend_score]}/100, Momentum #{data[:momentum_score]}/100"
      end
      analysis
    else
      puts "❌ Failed: #{result[:error]}"
      nil
    end
  end

  def mtf_screen(limit = 10)
    candidates = Screeners::SwingScreener.call(limit: limit)
    puts "\n📊 Top #{candidates.size} Candidates:"
    candidates.each_with_index do |c, idx|
      puts "#{idx + 1}. #{c[:symbol]}: #{c[:score]}/100 (MTF: #{c[:mtf_score]}/100)"
    end
    candidates
  end

  def mtf_signal(symbol = "RELIANCE")
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
      puts "\n📈 Signal: #{symbol}"
      puts "=" * 60
      puts "Entry: ₹#{signal[:entry_price]}"
      puts "SL: ₹#{signal[:sl]}"
      puts "TP: ₹#{signal[:tp]}"
      puts "RR: #{signal[:rr]}:1"
      puts "Qty: #{signal[:qty]}"
      puts "Confidence: #{signal[:confidence]}/100"
      signal
    else
      puts "❌ Signal generation failed"
      nil
    end
  end

  def ai_eval(symbol = "RELIANCE")
    signal = mtf_signal(symbol)
    return unless signal

    puts "\n🤖 AI Evaluation..."
    result = Strategies::Swing::AIEvaluator.call(signal)
    if result[:success]
      puts "AI Score: #{result[:ai_score]}/100"
      puts "Timeframe Alignment: #{result[:timeframe_alignment]}"
      puts "Entry Timing: #{result[:entry_timing]}"
      puts "Summary: #{result[:ai_summary]}"
      result
    else
      puts "❌ Failed: #{result[:error]}"
      nil
    end
  end

  def create_portfolio(name = "Test", equity = 500_000)
    portfolio = CapitalAllocationPortfolio.find_or_create_by(name: name) do |p|
      p.mode = "paper"
      p.total_equity = equity
      p.available_cash = equity
      p.swing_capital = 0
      p.long_term_capital = 0
      p.peak_equity = equity
    end

    Portfolio::CapitalBucketer.new(portfolio: portfolio).call
    portfolio.reload

    puts "\n💰 Portfolio: #{portfolio.name}"
    puts "Equity: ₹#{portfolio.total_equity.round(2)}"
    puts "Swing: ₹#{portfolio.swing_capital.round(2)}"
    puts "Long-Term: ₹#{portfolio.long_term_capital.round(2)}"
    puts "Cash: ₹#{portfolio.available_cash.round(2)}"
    portfolio
  end

  def position_size(symbol = "RELIANCE", entry = 2500, sl = 2400, portfolio_name = "Test Portfolio")
    portfolio = CapitalAllocationPortfolio.find_by(name: portfolio_name)
    return puts "❌ Portfolio not found. Create with: create_portfolio" unless portfolio

    instrument = Instrument.find_by(symbol_name: symbol.upcase)
    return puts "❌ Instrument not found" unless instrument

    result = Swing::PositionSizer.call(
      portfolio: portfolio,
      entry_price: entry.to_f,
      stop_loss: sl.to_f,
      instrument: instrument,
    )

    if result[:success]
      puts "\n📏 Position Sizing: #{symbol}"
      puts "=" * 60
      puts "Quantity: #{result[:quantity]} shares"
      puts "Capital: ₹#{result[:capital_required].round(2)}"
      puts "Risk: ₹#{result[:risk_amount].round(2)} (#{result[:risk_percentage]}%)"
      result
    else
      puts "❌ Failed: #{result[:error]}"
      nil
    end
  end

  def risk_check(portfolio_name = "Test Portfolio")
    portfolio = CapitalAllocationPortfolio.find_by(name: portfolio_name)
    return puts "❌ Portfolio not found" unless portfolio

    result = Portfolio::RiskManager.new(portfolio: portfolio).call
    puts "\n⚠️  Risk Check: #{portfolio_name}"
    puts "=" * 60
    result[:checks].each do |check, passed|
      puts "#{check.to_s.humanize}: #{passed ? '✅' : '❌'}"
    end
    puts "\nAllowed: #{result[:allowed] ? '✅ YES' : '❌ NO'}"
    result
  end
end

# Include in console
if defined?(Rails::Console)
  include ConsoleHelpers
  puts "\n✅ Console helpers loaded! Available methods:"
  puts "   - mtf_analyze(symbol)"
  puts "   - mtf_screen(limit)"
  puts "   - mtf_signal(symbol)"
  puts "   - ai_eval(symbol)"
  puts "   - create_portfolio(name, equity)"
  puts "   - position_size(symbol, entry, sl, portfolio_name)"
  puts "   - risk_check(portfolio_name)"
end
