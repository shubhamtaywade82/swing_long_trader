# frozen_string_literal: true

namespace :phase1 do
  desc "Verify Phase 1 completion: Outcome Tracking + Paper Trading + Metrics"
  task verify: :environment do
    puts "🔍 Phase 1 Verification"
    puts "=" * 60

    # 1. Check TradeOutcome model
    puts "\n1️⃣ TradeOutcome Model"
    if TradeOutcome.table_exists?
      puts "  ✅ Table exists"
      puts "  📊 Total outcomes: #{TradeOutcome.count}"
      puts "  📊 Open: #{TradeOutcome.open.count}"
      puts "  📊 Closed: #{TradeOutcome.closed.count}"
      puts "  📊 Winners: #{TradeOutcome.winners.count}"
      puts "  📊 Losers: #{TradeOutcome.losers.count}"
      
      if TradeOutcome.closed.any?
        win_rate = TradeOutcome.win_rate
        avg_r = TradeOutcome.average_r_multiple
        expectancy = TradeOutcome.expectancy
        puts "  📈 Win Rate: #{win_rate}%"
        puts "  📈 Avg R-Multiple: #{avg_r}"
        puts "  📈 Expectancy: #{expectancy.round(2)}"
      end
    else
      puts "  ❌ Table missing - run migrations"
    end

    # 2. Check ScreenerRun metrics
    puts "\n2️⃣ ScreenerRun Metrics"
    if ScreenerRun.table_exists?
      puts "  ✅ Table exists"
      recent_run = ScreenerRun.completed.recent.first
      if recent_run
        puts "  📊 Latest run: ##{recent_run.id} (#{recent_run.screener_type})"
        metrics = recent_run.metrics_hash
        puts "  📈 Eligible: #{metrics['eligible_count'] || 0}"
        puts "  📈 Ranked: #{metrics['ranked_count'] || 0}"
        puts "  📈 AI Evaluated: #{metrics['ai_evaluated_count'] || 0}"
        puts "  📈 Final: #{metrics['final_count'] || 0}"
        puts "  📈 AI Calls: #{recent_run.ai_calls_count || 0}"
        puts "  📈 AI Cost: $#{recent_run.ai_cost || 0}"
        puts "  📈 Overlap: #{metrics['overlap_with_prev_run'] || 0}%"
        
        health = recent_run.health_status
        if health[:healthy]
          puts "  ✅ Health: Healthy"
        else
          puts "  ⚠️  Health: Issues: #{health[:issues].join(', ')}"
        end
      else
        puts "  ⚠️  No completed runs found"
      end
    else
      puts "  ❌ Table missing - run migrations"
    end

    # 3. Check Paper Trading integration
    puts "\n3️⃣ Paper Trading Integration"
    if PaperPosition.table_exists?
      puts "  ✅ PaperPosition table exists"
      open_positions = PaperPosition.open.count
      puts "  📊 Open positions: #{open_positions}"
      
      # Check if positions have linked TradeOutcomes
      positions_with_outcomes = PaperPosition.open.joins("LEFT JOIN trade_outcomes ON trade_outcomes.position_id = paper_positions.id AND trade_outcomes.position_type = 'paper_position'")
                                             .where("trade_outcomes.id IS NOT NULL")
                                             .count
      puts "  📊 Positions with TradeOutcomes: #{positions_with_outcomes}/#{open_positions}"
      
      if open_positions > 0 && positions_with_outcomes < open_positions
        puts "  ⚠️  Some positions missing TradeOutcomes"
      end
    else
      puts "  ❌ PaperPosition table missing"
    end

    # 4. Check exit tracking
    puts "\n4️⃣ Exit Tracking"
    closed_outcomes = TradeOutcome.closed
    if closed_outcomes.any?
      exit_reasons = closed_outcomes.group(:exit_reason).count
      puts "  📊 Exit reasons:"
      exit_reasons.each do |reason, count|
        puts "    #{reason}: #{count}"
      end
      
      # Verify all required exit reasons are present
      required_reasons = %w[target_hit stop_hit time_based]
      missing = required_reasons - exit_reasons.keys
      if missing.any?
        puts "  ⚠️  Missing exit reasons: #{missing.join(', ')}"
      else
        puts "  ✅ All required exit reasons present"
      end
    else
      puts "  ⚠️  No closed outcomes yet"
    end

    # 5. Check end-to-end flow
    puts "\n5️⃣ End-to-End Flow"
    recent_run = ScreenerRun.completed.recent.first
    if recent_run
      tier1_count = recent_run.metrics_hash["tier_1_count"] || 0
      outcomes_count = TradeOutcome.where(screener_run_id: recent_run.id).count
      
      puts "  📊 Tier 1 candidates: #{tier1_count}"
      puts "  📊 TradeOutcomes created: #{outcomes_count}"
      
      if tier1_count > 0 && outcomes_count == 0
        puts "  ⚠️  TradeOutcomes not created for Tier 1 candidates"
      elsif tier1_count > 0 && outcomes_count > 0
        puts "  ✅ TradeOutcomes created for Tier 1 candidates"
      end
    end

    puts "\n" + "=" * 60
    puts "✅ Phase 1 Verification Complete"
  end

  desc "Test TradeOutcome creation from screener"
  task test_outcome_creation: :environment do
    puts "🧪 Testing TradeOutcome Creation"
    puts "=" * 60

    # Get latest screener run
    run = ScreenerRun.completed.recent.first
    unless run
      puts "❌ No completed screener runs found"
      exit 1
    end

    puts "Using ScreenerRun ##{run.id}"

    # Get a final candidate
    candidate_result = run.screener_results.by_stage("final").first
    unless candidate_result
      puts "❌ No final candidates found"
      exit 1
    end

    puts "Testing with candidate: #{candidate_result.symbol}"

    # Create TradeOutcome
    candidate_hash = candidate_result.to_candidate_hash.merge(
      tier: "tier_1",
      stage: "final",
    )

    result = TradeOutcomes::Creator.call(
      screener_run: run,
      candidate: candidate_hash,
      trading_mode: "paper",
    )

    if result[:success]
      outcome = result[:outcome]
      puts "✅ TradeOutcome created:"
      puts "  ID: #{outcome.id}"
      puts "  Symbol: #{outcome.symbol}"
      puts "  Entry Price: ₹#{outcome.entry_price}"
      puts "  Stop Loss: ₹#{outcome.stop_loss}"
      puts "  Take Profit: ₹#{outcome.take_profit}"
      puts "  Risk Amount: ₹#{outcome.risk_amount}"
      puts "  Status: #{outcome.status}"
    else
      puts "❌ Failed to create TradeOutcome: #{result[:error]}"
      exit 1
    end
  end
end
