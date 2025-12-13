# frozen_string_literal: true

namespace :test do
  namespace :mtf do
    desc "Test Multi-Timeframe Analyzer on a single instrument"
    task :analyzer, [:symbol] => :environment do |_t, args|
      symbol = args[:symbol] || "RELIANCE"
      puts "\n🔍 Testing Multi-Timeframe Analyzer for #{symbol}\n"
      puts "=" * 80

      instrument = Instrument.find_by(symbol_name: symbol.upcase)
      unless instrument
        puts "❌ Instrument not found: #{symbol}"
        exit 1
      end

      puts "📊 Instrument: #{instrument.symbol_name} (#{instrument.id})"
      puts "📅 Started at: #{Time.current}\n"

      result = Swing::MultiTimeframeAnalyzer.call(
        instrument: instrument,
        include_intraday: true,
      )

      if result[:success]
        analysis = result[:analysis]
        puts "✅ Analysis successful!\n"
        puts "\n📈 Multi-Timeframe Score: #{analysis[:multi_timeframe_score]}/100"
        puts "\n🎯 Trend Alignment:"
        ta = analysis[:trend_alignment]
        puts "   - Aligned: #{ta[:aligned] ? '✅ YES' : '❌ NO'}"
        puts "   - Bullish: #{ta[:bullish_count]}, Bearish: #{ta[:bearish_count]}, Neutral: #{ta[:neutral_count]}"

        puts "\n⚡ Momentum Alignment:"
        ma = analysis[:momentum_alignment]
        puts "   - Aligned: #{ma[:aligned] ? '✅ YES' : '❌ NO'}"
        puts "   - Bullish: #{ma[:bullish_count]}, Bearish: #{ma[:bearish_count]}, Neutral: #{ma[:neutral_count]}"

        puts "\n📊 Timeframe Analysis:"
        analysis[:timeframes].each do |tf_key, tf_data|
          puts "\n   #{tf_key.to_s.upcase} (#{tf_data[:timeframe]}):"
          puts "      - Candles: #{tf_data[:candles_count]}"
          puts "      - Latest Close: ₹#{tf_data[:latest_close]&.round(2)}"
          puts "      - Trend Score: #{tf_data[:trend_score]}/100"
          puts "      - Momentum Score: #{tf_data[:momentum_score]}/100"
          puts "      - Trend Direction: #{tf_data[:trend_direction]}"
          puts "      - Momentum Direction: #{tf_data[:momentum_direction]}"
        end

        puts "\n🛡️ Support/Resistance Levels:"
        sr = analysis[:support_resistance]
        puts "   Support: #{sr[:support_levels].map { |s| "₹#{s.round(2)}" }.join(', ')}"
        puts "   Resistance: #{sr[:resistance_levels].map { |r| "₹#{r.round(2)}" }.join(', ')}"

        if analysis[:entry_recommendations].any?
          puts "\n💡 Entry Recommendations:"
          analysis[:entry_recommendations].each_with_index do |rec, idx|
            puts "   #{idx + 1}. #{rec[:type].to_s.upcase}:"
            puts "      - Entry Zone: ₹#{rec[:entry_zone][0].round(2)} - ₹#{rec[:entry_zone][1].round(2)}"
            puts "      - Stop Loss: ₹#{rec[:stop_loss].round(2)}"
            puts "      - Confidence: #{rec[:confidence]}/100"
          end
        else
          puts "\n⚠️  No entry recommendations generated"
        end

        puts "\n✅ Test completed successfully!"
      else
        puts "❌ Analysis failed: #{result[:error]}"
        exit 1
      end
    end

    desc "Test Multi-Timeframe Screener (top N candidates)"
    task :screener, [:limit] => :environment do |_t, args|
      limit = (args[:limit] || 10).to_i
      puts "\n🔍 Testing Multi-Timeframe Swing Screener (Top #{limit})\n"
      puts "=" * 80

      start_time = Time.current
      candidates = Screeners::SwingScreener.call(limit: limit)

      if candidates.any?
        puts "✅ Found #{candidates.size} candidates\n"
        puts "📊 Results:\n"

        candidates.each_with_index do |candidate, idx|
          puts "\n#{idx + 1}. #{candidate[:symbol]}"
          puts "   Score: #{candidate[:score]}/100"
          puts "   Base Score: #{candidate[:base_score]}/100"
          puts "   MTF Score: #{candidate[:mtf_score]}/100"

          if candidate[:multi_timeframe]
            mtf = candidate[:multi_timeframe]
            puts "   Trend Aligned: #{mtf[:trend_alignment][:aligned] ? '✅' : '❌'}"
            puts "   Momentum Aligned: #{mtf[:momentum_alignment][:aligned] ? '✅' : '❌'}"
            puts "   Timeframes: #{mtf[:timeframes_analyzed]&.join(', ') || 'N/A'}"
          end

          indicators = candidate[:indicators] || {}
          puts "   EMA20: ₹#{indicators[:ema20]&.round(2) || 'N/A'}"
          puts "   RSI: #{indicators[:rsi]&.round(2) || 'N/A'}"
          puts "   ADX: #{indicators[:adx]&.round(2) || 'N/A'}"
        end

        duration = Time.current - start_time
        puts "\n⏱️  Duration: #{duration.round(2)}s"
        puts "✅ Test completed successfully!"
      else
        puts "⚠️  No candidates found"
      end
    end

    desc "Test Signal Builder with Multi-Timeframe"
    task :signal, [:symbol] => :environment do |_t, args|
      symbol = args[:symbol] || "RELIANCE"
      puts "\n🔍 Testing Signal Builder with MTF for #{symbol}\n"
      puts "=" * 80

      instrument = Instrument.find_by(symbol_name: symbol.upcase)
      unless instrument
        puts "❌ Instrument not found: #{symbol}"
        exit 1
      end

      daily_series = instrument.load_daily_candles(limit: 100)
      unless daily_series&.candles&.any?
        puts "❌ Failed to load daily candles"
        exit 1
      end

      weekly_series = instrument.load_weekly_candles(limit: 52)

      signal = Strategies::Swing::SignalBuilder.call(
        instrument: instrument,
        daily_series: daily_series,
        weekly_series: weekly_series,
      )

      if signal
        puts "✅ Signal generated successfully!\n"
        puts "📊 Signal Details:"
        puts "   Symbol: #{signal[:symbol]}"
        puts "   Direction: #{signal[:direction].to_s.upcase}"
        puts "   Entry Price: ₹#{signal[:entry_price]}"
        puts "   Stop Loss: ₹#{signal[:sl]}"
        puts "   Take Profit: ₹#{signal[:tp]}"
        puts "   Risk-Reward: #{signal[:rr]}:1"
        puts "   Quantity: #{signal[:qty]}"
        puts "   Confidence: #{signal[:confidence]}/100"
        puts "   Holding Days: #{signal[:holding_days_estimate]}"

        if signal[:metadata][:multi_timeframe]
          mtf = signal[:metadata][:multi_timeframe]
          puts "\n📈 Multi-Timeframe Data:"
          puts "   MTF Score: #{mtf[:score]}/100"
          puts "   Trend Aligned: #{mtf[:trend_alignment][:aligned] ? '✅' : '❌'}"
          puts "   Momentum Aligned: #{mtf[:momentum_alignment][:aligned] ? '✅' : '❌'}"
          puts "   Timeframes: #{mtf[:timeframes_analyzed]&.join(', ') || 'N/A'}"
          if mtf[:support_levels]&.any?
            puts "   Support Levels: #{mtf[:support_levels].first(3).map { |s| "₹#{s.round(2)}" }.join(', ')}"
          end
          if mtf[:resistance_levels]&.any?
            puts "   Resistance Levels: #{mtf[:resistance_levels].first(3).map { |r| "₹#{r.round(2)}" }.join(', ')}"
          end
        end

        puts "\n✅ Test completed successfully!"
      else
        puts "❌ Signal generation failed"
        exit 1
      end
    end

    desc "Test AI Evaluator with Multi-Timeframe"
    task :ai_eval, [:symbol] => :environment do |_t, args|
      symbol = args[:symbol] || "RELIANCE"
      puts "\n🤖 Testing AI Evaluator with MTF for #{symbol}\n"
      puts "=" * 80

      instrument = Instrument.find_by(symbol_name: symbol.upcase)
      unless instrument
        puts "❌ Instrument not found: #{symbol}"
        exit 1
      end

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
        exit 1
      end

      puts "📊 Signal Generated:"
      puts "   Entry: ₹#{signal[:entry_price]}, SL: ₹#{signal[:sl]}, TP: ₹#{signal[:tp]}"
      puts "   Confidence: #{signal[:confidence]}/100\n"

      puts "🤖 Calling AI Evaluator...\n"
      ai_result = Strategies::Swing::AIEvaluator.call(signal)

      if ai_result[:success]
        puts "✅ AI Evaluation successful!\n"
        puts "📊 AI Results:"
        puts "   AI Score: #{ai_result[:ai_score]}/100"
        puts "   AI Confidence: #{ai_result[:ai_confidence]}/100"
        puts "   Timeframe Alignment: #{ai_result[:timeframe_alignment]&.upcase || 'N/A'}"
        puts "   Entry Timing: #{ai_result[:entry_timing]&.upcase || 'N/A'}"
        puts "   Risk: #{ai_result[:ai_risk]&.upcase || 'N/A'}"
        puts "\n📝 Summary:"
        puts "   #{ai_result[:ai_summary]}"
        puts "\n💾 Cached: #{ai_result[:cached] ? 'Yes' : 'No'}"
        puts "\n✅ Test completed successfully!"
      else
        puts "❌ AI Evaluation failed: #{ai_result[:error]}"
        exit 1
      end
    end

    desc "Test AI Ranker with Multi-Timeframe"
    task :ai_rank, [:limit] => :environment do |_t, args|
      limit = (args[:limit] || 5).to_i
      puts "\n🤖 Testing AI Ranker with MTF (Top #{limit})\n"
      puts "=" * 80

      # Get candidates from screener
      puts "📊 Getting candidates from screener...\n"
      candidates = Screeners::SwingScreener.call(limit: limit * 2) # Get more for ranking

      unless candidates.any?
        puts "❌ No candidates found"
        exit 1
      end

      puts "✅ Found #{candidates.size} candidates\n"
      puts "🤖 Ranking with AI...\n"

      ranked = Screeners::AIRanker.call(candidates: candidates, limit: limit)

      if ranked.any?
        puts "✅ Ranking completed!\n"
        puts "\n📊 Ranked Results:\n"

        ranked.each_with_index do |candidate, idx|
          puts "\n#{idx + 1}. #{candidate[:symbol]}"
          puts "   Combined Score: #{candidate[:score] + (candidate[:ai_score] || 0)}/200"
          puts "   Screener Score: #{candidate[:score]}/100"
          puts "   AI Score: #{candidate[:ai_score] || 'N/A'}/100"
          puts "   AI Confidence: #{candidate[:ai_confidence] || 'N/A'}/100"
          puts "   Timeframe Alignment: #{candidate[:ai_timeframe_alignment]&.upcase || 'N/A'}"
          puts "   Risk: #{candidate[:ai_risk]&.upcase || 'N/A'}"
          puts "   Holding Days: #{candidate[:ai_holding_days] || 'N/A'}"
          if candidate[:ai_summary]
            puts "   Summary: #{candidate[:ai_summary][0..100]}..."
          end
        end

        puts "\n✅ Test completed successfully!"
      else
        puts "⚠️  No ranked candidates returned"
      end
    end

    desc "Test complete flow: Screener → Signal → AI Evaluation"
    task :full_flow, [:symbol] => :environment do |_t, args|
      symbol = args[:symbol] || "RELIANCE"
      puts "\n🔄 Testing Complete Flow for #{symbol}\n"
      puts "=" * 80

      instrument = Instrument.find_by(symbol_name: symbol.upcase)
      unless instrument
        puts "❌ Instrument not found: #{symbol}"
        exit 1
      end

      # Step 1: Multi-Timeframe Analysis
      puts "\n1️⃣ Multi-Timeframe Analysis..."
      mtf_result = Swing::MultiTimeframeAnalyzer.call(instrument: instrument, include_intraday: true)
      if mtf_result[:success]
        puts "   ✅ MTF Score: #{mtf_result[:analysis][:multi_timeframe_score]}/100"
        puts "   ✅ Trend Aligned: #{mtf_result[:analysis][:trend_alignment][:aligned] ? 'YES' : 'NO'}"
      else
        puts "   ❌ Failed: #{mtf_result[:error]}"
        exit 1
      end

      # Step 2: Signal Generation
      puts "\n2️⃣ Signal Generation..."
      daily_series = instrument.load_daily_candles(limit: 100)
      weekly_series = instrument.load_weekly_candles(limit: 52)

      signal = Strategies::Swing::SignalBuilder.call(
        instrument: instrument,
        daily_series: daily_series,
        weekly_series: weekly_series,
      )

      if signal
        puts "   ✅ Entry: ₹#{signal[:entry_price]}, SL: ₹#{signal[:sl]}, TP: ₹#{signal[:tp]}"
        puts "   ✅ Confidence: #{signal[:confidence]}/100"
      else
        puts "   ❌ Signal generation failed"
        exit 1
      end

      # Step 3: AI Evaluation
      puts "\n3️⃣ AI Evaluation..."
      ai_result = Strategies::Swing::AIEvaluator.call(signal)

      if ai_result[:success]
        puts "   ✅ AI Score: #{ai_result[:ai_score]}/100"
        puts "   ✅ Timeframe Alignment: #{ai_result[:timeframe_alignment]&.upcase || 'N/A'}"
        puts "   ✅ Entry Timing: #{ai_result[:entry_timing]&.upcase || 'N/A'}"
      else
        puts "   ⚠️  AI Evaluation failed: #{ai_result[:error]}"
      end

      # Summary
      puts "\n📊 Summary:"
      puts "   Symbol: #{signal[:symbol]}"
      puts "   Direction: #{signal[:direction].to_s.upcase}"
      puts "   Entry: ₹#{signal[:entry_price]}"
      puts "   Stop Loss: ₹#{signal[:sl]}"
      puts "   Take Profit: ₹#{signal[:tp]}"
      puts "   Risk-Reward: #{signal[:rr]}:1"
      puts "   Quantity: #{signal[:qty]}"
      puts "   Confidence: #{signal[:confidence]}/100"
      if ai_result[:success]
        puts "   AI Score: #{ai_result[:ai_score]}/100"
        puts "   AI Timeframe Alignment: #{ai_result[:timeframe_alignment]&.upcase || 'N/A'}"
      end

      puts "\n✅ Complete flow test finished!"
    end
  end
end
