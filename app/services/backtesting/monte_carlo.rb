# frozen_string_literal: true

module Backtesting
  # Monte Carlo simulation for backtesting
  # Randomizes trade sequences to analyze robustness and probability distributions
  class MonteCarlo < ApplicationService
    DEFAULT_SIMULATIONS = 1000
    CONFIDENCE_LEVELS = [0.90, 0.95, 0.99].freeze

    def self.call(positions:, initial_capital:, simulations: DEFAULT_SIMULATIONS, confidence_levels: CONFIDENCE_LEVELS)
      new(
        positions: positions,
        initial_capital: initial_capital,
        simulations: simulations,
        confidence_levels: confidence_levels
      ).call
    end

    def initialize(positions:, initial_capital:, simulations: DEFAULT_SIMULATIONS, confidence_levels: CONFIDENCE_LEVELS)
      @positions = positions.dup # Work with copy to avoid modifying original
      @initial_capital = initial_capital.to_f
      @simulations = simulations
      @confidence_levels = confidence_levels
      @simulation_results = []
    end

    def call
      return { success: false, error: 'No positions provided' } if @positions.empty?

      # Run Monte Carlo simulations
      @simulations.times do |i|
        Rails.logger.debug("[MonteCarlo] Running simulation #{i + 1}/#{@simulations}") if (i % 100).zero?

        result = run_simulation
        @simulation_results << result
      end

      # Analyze results
      analysis = analyze_results

      {
        success: true,
        simulations: @simulations,
        initial_capital: @initial_capital,
        results: analysis,
        probability_distributions: calculate_probability_distributions,
        confidence_intervals: calculate_confidence_intervals,
        worst_case_scenarios: analyze_worst_cases
      }
    end

    private

    def run_simulation
      # Randomize trade sequence
      randomized_positions = @positions.shuffle

      # Simulate portfolio with randomized sequence
      capital = @initial_capital
      equity_curve = [capital]
      max_equity = capital
      max_drawdown = 0.0
      total_trades = 0
      winning_trades = 0
      losing_trades = 0
      total_pnl = 0.0

      randomized_positions.each do |position|
        pnl = position.calculate_pnl
        capital += pnl
        total_pnl += pnl
        total_trades += 1

        if pnl > 0
          winning_trades += 1
        elsif pnl < 0
          losing_trades += 1
        end

        equity_curve << capital
        max_equity = [max_equity, capital].max
        drawdown = ((max_equity - capital) / max_equity * 100)
        max_drawdown = [max_drawdown, drawdown].max
      end

      total_return = capital > 0 ? ((capital - @initial_capital) / @initial_capital * 100) : 0
      win_rate = total_trades > 0 ? (winning_trades.to_f / total_trades * 100) : 0

      {
        final_capital: capital.round(2),
        total_return: total_return.round(2),
        total_pnl: total_pnl.round(2),
        max_drawdown: max_drawdown.round(2),
        total_trades: total_trades,
        winning_trades: winning_trades,
        losing_trades: losing_trades,
        win_rate: win_rate.round(2),
        equity_curve: equity_curve
      }
    end

    def analyze_results
      return {} if @simulation_results.empty?

      {
        mean_final_capital: mean(:final_capital),
        mean_total_return: mean(:total_return),
        mean_max_drawdown: mean(:max_drawdown),
        mean_win_rate: mean(:win_rate),
        std_dev_final_capital: standard_deviation(:final_capital),
        std_dev_total_return: standard_deviation(:total_return),
        std_dev_max_drawdown: standard_deviation(:max_drawdown),
        min_final_capital: min(:final_capital),
        max_final_capital: max(:final_capital),
        min_total_return: min(:total_return),
        max_total_return: max(:total_return),
        min_max_drawdown: min(:max_drawdown),
        max_max_drawdown: max(:max_drawdown)
      }
    end

    def calculate_probability_distributions
      return {} if @simulation_results.empty?

      returns = @simulation_results.map { |r| r[:total_return] }.sort
      drawdowns = @simulation_results.map { |r| r[:max_drawdown] }.sort

      {
        returns: {
          min: returns.first,
          q25: percentile(returns, 0.25),
          median: percentile(returns, 0.50),
          q75: percentile(returns, 0.75),
          max: returns.last,
          mean: mean(:total_return),
          std_dev: standard_deviation(:total_return)
        },
        drawdowns: {
          min: drawdowns.first,
          q25: percentile(drawdowns, 0.25),
          median: percentile(drawdowns, 0.50),
          q75: percentile(drawdowns, 0.75),
          max: drawdowns.last,
          mean: mean(:max_drawdown),
          std_dev: standard_deviation(:max_drawdown)
        }
      }
    end

    def calculate_confidence_intervals
      return {} if @simulation_results.empty?

      intervals = {}

      @confidence_levels.each do |level|
        alpha = 1 - level
        lower_percentile = (alpha / 2.0) * 100
        upper_percentile = (1 - alpha / 2.0) * 100

        returns = @simulation_results.map { |r| r[:total_return] }.sort
        drawdowns = @simulation_results.map { |r| r[:max_drawdown] }.sort

        intervals[level] = {
          total_return: {
            lower: percentile(returns, lower_percentile / 100.0),
            upper: percentile(returns, upper_percentile / 100.0),
            range: percentile(returns, upper_percentile / 100.0) - percentile(returns, lower_percentile / 100.0)
          },
          max_drawdown: {
            lower: percentile(drawdowns, lower_percentile / 100.0),
            upper: percentile(drawdowns, upper_percentile / 100.0),
            range: percentile(drawdowns, upper_percentile / 100.0) - percentile(drawdowns, lower_percentile / 100.0)
          }
        }
      end

      intervals
    end

    def analyze_worst_cases
      return {} if @simulation_results.empty?

      # Find worst 5% of simulations
      worst_count = (@simulation_results.size * 0.05).ceil
      worst_simulations = @simulation_results.sort_by { |r| r[:total_return] }.first(worst_count)

      {
        worst_5_percent: {
          count: worst_count,
          mean_return: worst_simulations.sum { |r| r[:total_return] } / worst_count.to_f,
          mean_drawdown: worst_simulations.sum { |r| r[:max_drawdown] } / worst_count.to_f,
          worst_return: worst_simulations.first[:total_return],
          worst_drawdown: worst_simulations.max_by { |r| r[:max_drawdown] }[:max_drawdown]
        },
        probability_of_loss: calculate_probability_of_loss,
        probability_of_large_drawdown: calculate_probability_of_large_drawdown
      }
    end

    def calculate_probability_of_loss
      losing_simulations = @simulation_results.count { |r| r[:total_return] < 0 }
      (losing_simulations.to_f / @simulation_results.size * 100).round(2)
    end

    def calculate_probability_of_large_drawdown
      # Large drawdown = > 20%
      large_dd_simulations = @simulation_results.count { |r| r[:max_drawdown] > 20.0 }
      (large_dd_simulations.to_f / @simulation_results.size * 100).round(2)
    end

    def mean(metric)
      values = @simulation_results.map { |r| r[metric] }
      return 0.0 if values.empty?

      (values.sum.to_f / values.size).round(2)
    end

    def standard_deviation(metric)
      values = @simulation_results.map { |r| r[metric] }
      return 0.0 if values.empty? || values.size == 1

      mean_value = mean(metric)
      variance = values.sum { |v| (v - mean_value)**2 } / (values.size - 1)
      Math.sqrt(variance).round(2)
    end

    def min(metric)
      @simulation_results.map { |r| r[metric] }.min
    end

    def max(metric)
      @simulation_results.map { |r| r[metric] }.max
    end

    def percentile(sorted_array, percentile)
      return sorted_array.first if sorted_array.empty?
      return sorted_array.last if percentile >= 1.0

      index = (percentile * (sorted_array.size - 1)).ceil
      sorted_array[index] || sorted_array.last
    end
  end
end

