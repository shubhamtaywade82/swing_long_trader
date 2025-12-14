# frozen_string_literal: true

module ScreenerRuns
  # Monitors screener run health and alerts on anomalies
  class HealthMonitor < ApplicationService
    def self.check_recent_runs(limit: 10)
      new.check_recent_runs(limit: limit)
    end

    def check_recent_runs(limit: 10)
      recent_runs = ScreenerRun.completed
                                .order(started_at: :desc)
                                .limit(limit)

      issues = []
      trends = analyze_trends(recent_runs)

      recent_runs.each do |run|
        health = run.health_status
        
        unless health[:healthy]
          issues << {
            run_id: run.id,
            started_at: run.started_at,
            issues: health[:issues],
            metrics: {
              compression: health[:compression_efficiency],
              eligible: health[:eligible_count],
              final: health[:final_count],
              overlap: health[:overlap],
              ai_cost: health[:ai_cost],
            },
          }
        end
      end

      {
        total_runs_checked: recent_runs.count,
        runs_with_issues: issues.size,
        issues: issues,
        trends: trends,
        overall_health: issues.empty? ? "healthy" : "degraded",
      }
    end

    private

    def analyze_trends(runs)
      return {} if runs.empty?

      compressions = runs.map { |r| r.compression_efficiency }
      overlaps = runs.map { |r| r.overlap_with_previous_run }
      ai_costs = runs.map { |r| r.metrics_hash["ai_cost"] || 0 }

      {
        compression_trend: calculate_trend(compressions),
        overlap_trend: calculate_trend(overlaps),
        ai_cost_trend: calculate_trend(ai_costs),
        avg_compression: compressions.sum / compressions.size,
        avg_overlap: overlaps.sum / overlaps.size,
        avg_ai_cost: ai_costs.sum / ai_costs.size,
      }
    end

    def calculate_trend(values)
      return "stable" if values.size < 2

      # Simple trend: compare first half vs second half
      midpoint = values.size / 2
      first_half_avg = values.first(midpoint).sum / midpoint
      second_half_avg = values.last(values.size - midpoint).sum / (values.size - midpoint)

      if second_half_avg > first_half_avg * 1.1
        "increasing"
      elsif second_half_avg < first_half_avg * 0.9
        "decreasing"
      else
        "stable"
      end
    end
  end
end
