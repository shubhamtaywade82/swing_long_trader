# frozen_string_literal: true

module Telegram
  class AlertFormatter
    def self.format_daily_candidates(candidates)
      new.format_daily_candidates(candidates)
    end

    def self.format_signal_alert(signal)
      new.format_signal_alert(signal)
    end

    def self.format_exit_alert(signal, exit_reason:, exit_price:, pnl:)
      new.format_exit_alert(signal, exit_reason: exit_reason, exit_price: exit_price, pnl: pnl)
    end

    def self.format_portfolio_snapshot(portfolio_data)
      new.format_portfolio_snapshot(portfolio_data)
    end

    def self.format_error_alert(error_message, context: nil)
      new.format_error_alert(error_message, context: context)
    end

    def self.format_tiered_candidates(final_result)
      new.format_tiered_candidates(final_result)
    end

    def format_daily_candidates(candidates)
      return "📋 <b>Daily Candidates</b>\n\nNo candidates found today." if candidates.empty?

      message = "📋 <b>Daily Candidates</b> (#{candidates.size})\n\n"

      candidates.first(10).each_with_index do |candidate, index|
        symbol = candidate[:symbol] || candidate[:instrument_id]
        score = candidate[:score] || 0
        ai_score = candidate[:ai_score]
        direction = candidate[:direction] || "long"

        emoji = direction == "long" ? "🟢" : "🔴"
        rank = index + 1

        message += "#{rank}. #{emoji} <b>#{symbol}</b>\n"
        message += "   Score: #{score.round(1)}"
        message += " | AI: #{ai_score.round(1)}" if ai_score
        message += "\n"

        if candidate[:metadata]
          indicators = candidate[:metadata][:trend_alignment] || []
          message += "   #{indicators.join(', ')}\n" if indicators.any?
        end

        message += "\n"
      end

      message += "⏰ #{Time.current.strftime('%Y-%m-%d %H:%M:%S IST')}"

      message
    end

    def format_signal_alert(signal)
      symbol = escape_html(signal[:symbol] || "N/A")
      direction = signal[:direction] || :long
      entry_price = signal[:entry_price] || 0
      sl = signal[:sl] || 0
      tp = signal[:tp] || 0
      rr = signal[:rr] || 0
      qty = signal[:qty] || 0
      confidence = signal[:confidence] || 0
      holding_days = signal[:holding_days_estimate] || 0

      emoji = direction == :long ? "🟢" : "🔴"
      direction_text = direction.to_s.upcase

      message = "#{emoji} <b>Swing Signal</b>\n\n"
      message += "📊 <b>Symbol:</b> #{symbol}\n"
      message += "🎯 <b>Direction:</b> #{direction_text}\n"
      message += "💰 <b>Entry:</b> ₹#{entry_price.round(2)}\n"
      message += "🛑 <b>Stop Loss:</b> ₹#{sl.round(2)}\n"
      message += "🎯 <b>Take Profit:</b> ₹#{tp.round(2)}\n"
      message += "📈 <b>Risk-Reward:</b> 1:#{rr.round(2)}\n"
      message += "📦 <b>Quantity:</b> #{qty}\n"
      message += "💪 <b>Confidence:</b> #{confidence.round(1)}%\n"
      message += "⏳ <b>Holding Days:</b> #{holding_days} days\n"

      if signal[:metadata]
        atr_pct = signal[:metadata][:atr_pct]
        message += "📊 <b>ATR %:</b> #{atr_pct.round(2)}%\n" if atr_pct
      end

      message += "\n⏰ #{Time.current.strftime('%H:%M:%S IST')}"

      message
    end

    def format_exit_alert(signal, exit_reason:, exit_price:, pnl:)
      symbol = signal[:symbol] || "N/A"
      entry_price = signal[:entry_price] || 0
      pnl_value = pnl.to_f
      qty = signal[:qty] || 1
      pnl_pct = entry_price.positive? ? ((pnl_value / (entry_price * qty)) * 100).round(2) : 0

      emoji = if pnl_value.positive?
                "✅"
              elsif pnl_value.negative?
                "❌"
              else
                "⚪"
              end

      message = "#{emoji} <b>Exit Alert</b>\n\n"
      message += "📊 <b>Symbol:</b> #{symbol}\n"
      message += "💰 <b>Entry:</b> ₹#{entry_price.round(2)}\n"
      message += "💵 <b>Exit:</b> ₹#{exit_price.round(2)}\n"
      message += "💸 <b>PnL:</b> ₹#{pnl_value.round(2)}"

      if pnl_pct.zero?
        message += "\n"
      else
        pnl_emoji = pnl_pct.positive? ? "📈" : "📉"
        message += " (#{pnl_emoji} #{'+' if pnl_pct.positive?}#{pnl_pct}%)\n"
      end

      message += "📝 <b>Reason:</b> #{exit_reason}\n"
      message += "⏰ <b>Time:</b> #{Time.current.strftime('%H:%M:%S IST')}"

      message
    end

    def format_portfolio_snapshot(portfolio_data)
      total_pnl = portfolio_data[:total_pnl] || 0
      total_pnl_pct = portfolio_data[:total_pnl_pct] || 0
      open_positions = portfolio_data[:open_positions] || 0
      closed_positions = portfolio_data[:closed_positions] || 0
      win_rate = portfolio_data[:win_rate] || 0

      emoji = if total_pnl.positive?
                "📈"
              else
                total_pnl.negative? ? "📉" : "➡️"
              end

      message = "#{emoji} <b>Portfolio Snapshot</b>\n\n"
      message += "💸 <b>Total P&L:</b> ₹#{total_pnl.round(2)}"
      message += " (#{'+' if total_pnl_pct.positive?}#{total_pnl_pct.round(2)}%)\n"
      message += "📊 <b>Open Positions:</b> #{open_positions}\n"
      message += "✅ <b>Closed Positions:</b> #{closed_positions}\n"
      message += "🎯 <b>Win Rate:</b> #{win_rate.round(1)}%\n"

      if portfolio_data[:positions]&.any?
        message += "\n<b>Open Positions:</b>\n"
        portfolio_data[:positions].first(5).each do |pos|
          pos_pnl = pos[:pnl] || 0
          pos_emoji = pos_pnl.positive? ? "🟢" : "🔴"
          message += "#{pos_emoji} #{pos[:symbol]}: ₹#{pos_pnl.round(2)}\n"
        end
      end

      message += "\n⏰ #{Time.current.strftime('%Y-%m-%d %H:%M:%S IST')}"

      message
    end

    def format_error_alert(error_message, context: nil)
      message = "🚨 <b>Error Alert</b>\n\n"
      message += "#{error_message}\n"

      message += "\n<b>Context:</b> #{context}\n" if context

      message += "\n⏰ #{Time.current.strftime('%H:%M:%S IST')}"

      message
    end

    def format_tiered_candidates(final_result)
      summary = final_result[:summary] || {}
      tiers = final_result[:tiers] || {}
      tier_1 = tiers[:tier_1] || []
      tier_2 = tiers[:tier_2] || []
      tier_3 = tiers[:tier_3] || []

      message = "📊 <b>Swing Trading Candidates</b>\n\n"
      message += "📈 Screened: #{summary[:swing_count] || 0} → Selected: #{summary[:swing_selected] || 0}\n\n"

      # Tier 1: Actionable Now (3-5)
      if tier_1.any?
        message += "✅ <b>TIER 1: Actionable Now</b> (#{tier_1.size})\n"
        tier_1.each_with_index do |candidate, index|
          message += format_candidate(candidate, index + 1, actionable: true)
        end
        message += "\n"
      end

      # Tier 2: Watchlist / Waiting (5-10)
      if tier_2.any?
        message += "👀 <b>TIER 2: Watchlist / Waiting</b> (#{tier_2.size})\n"
        tier_2.first(5).each_with_index do |candidate, index|
          message += format_candidate(candidate, index + 1, actionable: false)
        end
        message += "\n"
      end

      # Tier 3: Market Strength (Rest)
      if tier_3.any?
        message += "📊 <b>TIER 3: Market Strength</b> (#{tier_3.size} bullish but extended)\n"
        message += "<i>Informational only - not actionable</i>\n\n"
      end

      message += "⏰ #{Time.current.strftime('%Y-%m-%d %H:%M:%S IST')}"

      message
    end

    def format_candidate(candidate, rank, actionable: false)
      symbol = candidate[:symbol] || "N/A"
      combined_score = candidate[:combined_score] || candidate[:score] || 0
      quality_score = candidate[:trade_quality_score]
      ai_confidence = candidate[:ai_confidence]
      sector = candidate[:sector]

      message = "#{rank}. <b>#{symbol}</b>"
      message += " (#{sector})" if sector
      message += "\n"

      # Scores
      score_parts = []
      score_parts << "Score: #{combined_score.round(1)}" if combined_score.positive?
      score_parts << "Quality: #{quality_score.round(1)}" if quality_score
      score_parts << "AI: #{ai_confidence.round(1)}/10" if ai_confidence
      message += "   #{score_parts.join(' | ')}\n" if score_parts.any?

      # AI comment if available
      if candidate[:ai_comment].present?
        message += "   💬 #{candidate[:ai_comment].truncate(80)}\n"
      end

      # Actionable details
      if actionable && candidate[:indicators]
        indicators = candidate[:indicators]
        latest_close = indicators[:latest_close]
        ema20 = indicators[:ema20]
        atr = indicators[:atr]

        if latest_close && ema20 && atr
          # Estimate entry, SL, TP
          entry = ema20 || latest_close
          sl = entry - (atr * 2)
          tp = entry + (atr * 2.5)
          rr = ((tp - entry) / (entry - sl)).round(2) if entry > sl

          message += "   💰 Entry: ₹#{entry.round(2)} | SL: ₹#{sl.round(2)} | TP: ₹#{tp.round(2)}"
          message += " | RR: 1:#{rr}" if rr
          message += "\n"
        end
      end

      message += "\n"
      message
    end

    private

    def escape_html(text)
      return text if text.nil?

      text.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub('"', "&quot;")
          .gsub("'", "&#39;")
    end
  end
end
