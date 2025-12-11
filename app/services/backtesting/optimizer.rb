# frozen_string_literal: true

module Backtesting
  # Parameter optimization using grid search
  # Uses walk-forward analysis to avoid overfitting
  class Optimizer < ApplicationService
    def self.call(instruments:, from_date:, to_date:, initial_capital: 100_000, parameter_ranges: {}, optimization_metric: :sharpe_ratio, use_walk_forward: true, backtester_class: SwingBacktester)
      new(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date,
        initial_capital: initial_capital,
        parameter_ranges: parameter_ranges,
        optimization_metric: optimization_metric,
        use_walk_forward: use_walk_forward,
        backtester_class: backtester_class
      ).call
    end

    def initialize(instruments:, from_date:, to_date:, initial_capital: 100_000, parameter_ranges: {}, optimization_metric: :sharpe_ratio, use_walk_forward: true, backtester_class: SwingBacktester)
      @instruments = instruments
      @from_date = from_date
      @to_date = to_date
      @initial_capital = initial_capital
      @parameter_ranges = parameter_ranges
      @optimization_metric = optimization_metric.to_sym
      @use_walk_forward = use_walk_forward
      @backtester_class = backtester_class
      @results = []
    end

    def call
      # Generate all parameter combinations
      combinations = generate_combinations(@parameter_ranges)
      total_combinations = combinations.size

      Rails.logger.info("[Optimizer] Testing #{total_combinations} parameter combinations...")

      # Test each combination
      combinations.each_with_index do |params, index|
        Rails.logger.info("[Optimizer] Testing combination #{index + 1}/#{total_combinations}: #{params.inspect}")

        result = test_parameters(params)
        next unless result[:success]

        @results << {
          parameters: params,
          metrics: result[:metrics],
          score: calculate_score(result[:metrics])
        }
      end

      # Sort by optimization metric
      @results.sort_by! { |r| -r[:score] } # Descending order

      # Generate sensitivity analysis
      sensitivity = calculate_sensitivity_analysis

      {
        success: true,
        best_parameters: @results.first&.dig(:parameters),
        best_metrics: @results.first&.dig(:metrics),
        all_results: @results,
        sensitivity_analysis: sensitivity,
        total_combinations_tested: @results.size
      }
    end

    private

    def generate_combinations(ranges)
      return [{}] if ranges.empty?

      # Generate cartesian product of all parameter ranges
      keys = ranges.keys
      values = ranges.values.map { |range| range.is_a?(Range) ? range.to_a : range }

      # Handle single value (not a range)
      values = values.map { |v| v.is_a?(Array) ? v : [v] }

      # Generate all combinations
      first_key = keys.first
      first_values = values.first

      if keys.size == 1
        first_values.map { |v| { first_key => v } }
      else
        remaining_keys = keys[1..]
        remaining_values = values[1..]
        remaining_combinations = generate_combinations(
          remaining_keys.zip(remaining_values).to_h
        )

        first_values.flat_map do |first_value|
          remaining_combinations.map do |remaining_combo|
            { first_key => first_value }.merge(remaining_combo)
          end
        end
      end
    end

    def test_parameters(params)
      if @use_walk_forward
        # Use walk-forward analysis to avoid overfitting
        walk_forward_result = WalkForward.call(
          instruments: @instruments,
          from_date: @from_date,
          to_date: @to_date,
          initial_capital: @initial_capital,
          window_type: :rolling,
          in_sample_days: 90,
          out_of_sample_days: 30,
          backtester_class: @backtester_class,
          backtester_options: build_backtester_options(params)
        )

        return { success: false } unless walk_forward_result[:success]

        # Use out-of-sample performance for optimization
        oos_agg = walk_forward_result[:aggregated][:out_of_sample]
        {
          success: true,
          metrics: {
            total_return: oos_agg[:avg_total_return] || 0,
            annualized_return: oos_agg[:avg_annualized_return] || 0,
            max_drawdown: oos_agg[:avg_max_drawdown] || 0,
            sharpe_ratio: oos_agg[:avg_sharpe_ratio] || 0,
            sortino_ratio: oos_agg[:avg_sortino_ratio] || 0,
            win_rate: oos_agg[:avg_win_rate] || 0,
            profit_factor: oos_agg[:avg_profit_factor] || 0,
            total_trades: oos_agg[:total_trades] || 0
          },
          walk_forward: walk_forward_result
        }
      else
        # Simple backtest (faster but may overfit)
        backtest_result = @backtester_class.call(
          instruments: @instruments,
          from_date: @from_date,
          to_date: @to_date,
          initial_capital: @initial_capital,
          **build_backtester_options(params)
        )

        return { success: false } unless backtest_result[:success]

        {
          success: true,
          metrics: backtest_result[:results]
        }
      end
    end

    def build_backtester_options(params)
      options = {}

      # Map parameter names to backtester options
      # This is strategy-specific and may need customization
      params.each do |key, value|
        case key.to_s
        when /stop_loss_pct/
          options[:stop_loss_pct] = value
        when /profit_target_pct/
          options[:profit_target_pct] = value
        when /trailing_stop_pct/
          options[:trailing_stop_pct] = value
        when /risk_per_trade/
          options[:risk_per_trade] = value
        else
          # Store in strategy_overrides for strategy engine
          options[:strategy_overrides] ||= {}
          options[:strategy_overrides][key] = value
        end
      end

      options
    end

    def calculate_score(metrics)
      case @optimization_metric
      when :sharpe_ratio
        metrics[:sharpe_ratio] || 0
      when :sortino_ratio
        metrics[:sortino_ratio] || 0
      when :total_return
        metrics[:total_return] || 0
      when :annualized_return
        metrics[:annualized_return] || 0
      when :profit_factor
        metrics[:profit_factor] || 0
      when :win_rate
        metrics[:win_rate] || 0
      when :composite
        # Composite score: weighted combination
        (metrics[:sharpe_ratio] || 0) * 0.4 +
          (metrics[:total_return] || 0) * 0.2 +
          (metrics[:win_rate] || 0) * 0.2 +
          (metrics[:profit_factor] || 0) * 0.2
      else
        metrics[@optimization_metric] || 0
      end
    end

    def calculate_sensitivity_analysis
      return {} if @results.empty?

      # Group results by parameter to see sensitivity
      sensitivity = {}

      # Get all parameter names
      param_names = @results.first[:parameters].keys

      param_names.each do |param_name|
        # Group by this parameter value
        grouped = @results.group_by { |r| r[:parameters][param_name] }

        # Calculate average score for each value
        param_sensitivity = grouped.map do |value, results|
          avg_score = results.sum { |r| r[:score] } / results.size.to_f
          {
            value: value,
            avg_score: avg_score.round(2),
            count: results.size
          }
        end.sort_by { |s| -s[:avg_score] }

        sensitivity[param_name] = {
          best_value: param_sensitivity.first[:value],
          best_score: param_sensitivity.first[:avg_score],
          all_values: param_sensitivity
        }
      end

      sensitivity
    end
  end
end

