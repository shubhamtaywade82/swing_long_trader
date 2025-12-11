# frozen_string_literal: true

module Backtesting
  # Walk-forward analysis for backtesting
  # Splits data into in-sample (training) and out-of-sample (testing) periods
  class WalkForward < ApplicationService
    WINDOW_TYPES = %i[rolling expanding].freeze

    def self.call(instruments:, from_date:, to_date:, initial_capital: 100_000, window_type: :rolling, in_sample_days: 90, out_of_sample_days: 30, backtester_class: SwingBacktester, backtester_options: {})
      new(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date,
        initial_capital: initial_capital,
        window_type: window_type,
        in_sample_days: in_sample_days,
        out_of_sample_days: out_of_sample_days,
        backtester_class: backtester_class,
        backtester_options: backtester_options
      ).call
    end

    def initialize(instruments:, from_date:, to_date:, initial_capital: 100_000, window_type: :rolling, in_sample_days: 90, out_of_sample_days: 30, backtester_class: SwingBacktester, backtester_options: {})
      @instruments = instruments
      @from_date = from_date
      @to_date = to_date
      @initial_capital = initial_capital
      @window_type = window_type.to_sym
      @in_sample_days = in_sample_days
      @out_of_sample_days = out_of_sample_days
      @backtester_class = backtester_class
      @backtester_options = backtester_options

      validate_window_type!
    end

    def call
      windows = generate_windows
      return { success: false, error: 'No valid windows generated' } if windows.empty?

      in_sample_results = []
      out_of_sample_results = []
      all_results = []

      windows.each_with_index do |window, index|
        # Run in-sample backtest
        in_sample_result = run_backtest(
          from_date: window[:in_sample_start],
          to_date: window[:in_sample_end],
          window_index: index,
          period_type: 'in_sample'
        )

        next unless in_sample_result[:success]

        in_sample_results << {
          window_index: index,
          start_date: window[:in_sample_start],
          end_date: window[:in_sample_end],
          results: in_sample_result[:results]
        }

        # Run out-of-sample backtest
        out_of_sample_result = run_backtest(
          from_date: window[:out_of_sample_start],
          to_date: window[:out_of_sample_end],
          window_index: index,
          period_type: 'out_of_sample',
          initial_capital: @initial_capital # Reset capital for each OOS period
        )

        next unless out_of_sample_result[:success]

        out_of_sample_results << {
          window_index: index,
          start_date: window[:out_of_sample_start],
          end_date: window[:out_of_sample_end],
          results: out_of_sample_result[:results]
        }

        all_results << {
          window_index: index,
          in_sample: in_sample_result[:results],
          out_of_sample: out_of_sample_result[:results]
        }
      end

      # Aggregate results
      aggregated = aggregate_results(in_sample_results, out_of_sample_results)

      {
        success: true,
        windows: windows,
        in_sample_results: in_sample_results,
        out_of_sample_results: out_of_sample_results,
        aggregated: aggregated,
        comparison: compare_in_sample_vs_out_of_sample(in_sample_results, out_of_sample_results)
      }
    end

    private

    def validate_window_type!
      return if WINDOW_TYPES.include?(@window_type)

      raise ArgumentError, "Invalid window_type: #{@window_type}. Must be one of: #{WINDOW_TYPES.join(', ')}"
    end

    def generate_windows
      windows = []
      current_date = @from_date

      while current_date < @to_date
        # In-sample period
        in_sample_start = current_date
        in_sample_end = current_date + @in_sample_days.days

        # Out-of-sample period
        out_of_sample_start = in_sample_end + 1.day
        out_of_sample_end = out_of_sample_start + @out_of_sample_days.days - 1.day

        # Skip if out-of-sample period extends beyond available data
        break if out_of_sample_end > @to_date

        windows << {
          in_sample_start: in_sample_start,
          in_sample_end: in_sample_end,
          out_of_sample_start: out_of_sample_start,
          out_of_sample_end: out_of_sample_end
        }

        # Move to next window
        case @window_type
        when :rolling
          # Rolling window: move forward by out-of-sample period
          current_date = out_of_sample_start
        when :expanding
          # Expanding window: keep expanding in-sample, move OOS forward
          current_date = out_of_sample_start
          # In expanding window, in_sample_start stays at @from_date
          # We'll adjust this in the loop
        end
      end

      # For expanding windows, adjust in_sample_start
      if @window_type == :expanding
        windows.each_with_index do |window, index|
          window[:in_sample_start] = @from_date
          window[:in_sample_end] = window[:out_of_sample_start] - 1.day
        end
      end

      windows
    end

    def run_backtest(from_date:, to_date:, window_index:, period_type:, initial_capital: @initial_capital)
      options = @backtester_options.merge(
        instruments: @instruments,
        from_date: from_date,
        to_date: to_date,
        initial_capital: initial_capital
      )

      @backtester_class.call(**options)
    end

    def aggregate_results(in_sample_results, out_of_sample_results)
      {
        in_sample: aggregate_period_results(in_sample_results),
        out_of_sample: aggregate_period_results(out_of_sample_results)
      }
    end

    def aggregate_period_results(period_results)
      return {} if period_results.empty?

      # Calculate averages across all periods
      {
        avg_total_return: average_metric(period_results, :total_return),
        avg_annualized_return: average_metric(period_results, :annualized_return),
        avg_max_drawdown: average_metric(period_results, :max_drawdown),
        avg_sharpe_ratio: average_metric(period_results, :sharpe_ratio),
        avg_sortino_ratio: average_metric(period_results, :sortino_ratio),
        avg_win_rate: average_metric(period_results, :win_rate),
        avg_profit_factor: average_metric(period_results, :profit_factor),
        total_trades: sum_metric(period_results, :total_trades),
        avg_trades_per_period: average_metric(period_results, :total_trades),
        periods_count: period_results.size
      }
    end

    def average_metric(period_results, metric_key)
      values = period_results.map { |r| r[:results][metric_key] }.compact
      return 0.0 if values.empty?

      (values.sum.to_f / values.size).round(2)
    end

    def sum_metric(period_results, metric_key)
      period_results.sum { |r| r[:results][metric_key].to_i }
    end

    def compare_in_sample_vs_out_of_sample(in_sample_results, out_of_sample_results)
      in_sample_agg = aggregate_period_results(in_sample_results)
      out_of_sample_agg = aggregate_period_results(out_of_sample_results)

      {
        return_degradation: calculate_degradation(in_sample_agg[:avg_total_return], out_of_sample_agg[:avg_total_return]),
        sharpe_degradation: calculate_degradation(in_sample_agg[:avg_sharpe_ratio], out_of_sample_agg[:avg_sharpe_ratio]),
        drawdown_increase: calculate_increase(in_sample_agg[:avg_max_drawdown], out_of_sample_agg[:avg_max_drawdown]),
        win_rate_degradation: calculate_degradation(in_sample_agg[:avg_win_rate], out_of_sample_agg[:avg_win_rate]),
        profit_factor_degradation: calculate_degradation(in_sample_agg[:avg_profit_factor], out_of_sample_agg[:avg_profit_factor]),
        consistency_score: calculate_consistency_score(in_sample_results, out_of_sample_results)
      }
    end

    def calculate_degradation(in_sample_value, out_of_sample_value)
      return 0.0 if in_sample_value.zero? || in_sample_value.nil? || out_of_sample_value.nil?

      ((in_sample_value - out_of_sample_value) / in_sample_value.abs * 100).round(2)
    end

    def calculate_increase(in_sample_value, out_of_sample_value)
      return 0.0 if in_sample_value.zero? || in_sample_value.nil? || out_of_sample_value.nil?

      ((out_of_sample_value - in_sample_value) / in_sample_value.abs * 100).round(2)
    end

    def calculate_consistency_score(in_sample_results, out_of_sample_results)
      return 0.0 if in_sample_results.empty? || out_of_sample_results.empty?

      # Calculate how consistent OOS performance is with IS performance
      # Score ranges from 0-100, where 100 means perfect consistency
      consistency_scores = []

      in_sample_results.each_with_index do |is_result, index|
        oos_result = out_of_sample_results[index]
        next unless oos_result

        is_return = is_result[:results][:total_return] || 0
        oos_return = oos_result[:results][:total_return] || 0

        # Penalize if OOS is significantly worse than IS
        if oos_return < is_return * 0.5 # OOS is less than 50% of IS
          consistency_scores << 0
        elsif oos_return >= is_return * 0.8 # OOS is at least 80% of IS
          consistency_scores << 100
        else
          # Linear interpolation between 0 and 100
          ratio = (oos_return - is_return * 0.5) / (is_return * 0.3)
          consistency_scores << (ratio * 100).clamp(0, 100)
        end
      end

      return 0.0 if consistency_scores.empty?

      (consistency_scores.sum.to_f / consistency_scores.size).round(2)
    end
  end
end

