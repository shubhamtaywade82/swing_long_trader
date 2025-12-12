# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtesting::WalkForward, type: :service do
  let(:instrument) { create(:instrument) }
  let(:instruments) { Instrument.where(id: instrument.id) }
  let(:from_date) { 200.days.ago.to_date }
  let(:to_date) { Date.today }

  describe '.call' do
    it 'delegates to instance method' do
      allow_any_instance_of(described_class).to receive(:call).and_return({ success: true })

      described_class.call(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date
      )

      expect_any_instance_of(described_class).to have_received(:call)
    end
  end

  describe '#call' do
    before do
      allow(Backtesting::SwingBacktester).to receive(:call).and_return(
        {
          success: true,
          results: {
            total_return: 10.0,
            sharpe_ratio: 1.5
          }
        }
      )
      allow(Backtesting::DataLoader).to receive(:load_for_instruments).and_return({})
    end

    it 'generates walk-forward windows' do
      result = described_class.new(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date,
        in_sample_days: 90,
        out_of_sample_days: 30
      ).call

      expect(result[:success]).to be true
      expect(result[:windows]).to be_present
    end

    it 'runs in-sample and out-of-sample backtests' do
      result = described_class.new(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date,
        in_sample_days: 90,
        out_of_sample_days: 30
      ).call

      expect(result[:in_sample_results]).to be_present
      expect(result[:out_of_sample_results]).to be_present
    end

    context 'when window type is expanding' do
      it 'uses expanding windows' do
        result = described_class.new(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date,
          window_type: :expanding
        ).call

        expect(result[:success]).to be true
      end
    end

    context 'when window type is invalid' do
      it 'raises ArgumentError' do
        expect do
          described_class.new(
            instruments: instruments,
            from_date: from_date,
            to_date: to_date,
            window_type: :invalid
          )
        end.to raise_error(ArgumentError, /Invalid window_type/)
      end
    end

    context 'when no valid windows can be generated' do
      it 'returns error' do
        # Date range too short for windows
        short_from = 10.days.ago.to_date
        short_to = Date.today

        result = described_class.new(
          instruments: instruments,
          from_date: short_from,
          to_date: short_to,
          in_sample_days: 90,
          out_of_sample_days: 30
        ).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('No valid windows generated')
      end
    end

    context 'when backtest fails' do
      before do
        allow(Backtesting::SwingBacktester).to receive(:call).and_return(
          { success: false, error: 'Backtest failed' }
        )
      end

      it 'skips failed backtests' do
        result = described_class.new(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date,
          in_sample_days: 90,
          out_of_sample_days: 30
        ).call

        expect(result[:success]).to be true
        expect(result[:in_sample_results]).to be_empty
      end
    end

    describe 'private methods' do
      let(:walk_forward) do
        described_class.new(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date,
          in_sample_days: 90,
          out_of_sample_days: 30
        )
      end

      describe '#generate_windows' do
        it 'generates rolling windows' do
          windows = walk_forward.send(:generate_windows)

          expect(windows).to be_an(Array)
          windows.each do |window|
            expect(window).to have_key(:in_sample_start)
            expect(window).to have_key(:in_sample_end)
            expect(window).to have_key(:out_of_sample_start)
            expect(window).to have_key(:out_of_sample_end)
          end
        end

        it 'generates expanding windows' do
          walk_forward = described_class.new(
            instruments: instruments,
            from_date: from_date,
            to_date: to_date,
            window_type: :expanding,
            in_sample_days: 90,
            out_of_sample_days: 30
          )

          windows = walk_forward.send(:generate_windows)

          expect(windows).to be_an(Array)
          # In expanding windows, in_sample_start should be @from_date for all windows
          windows.each do |window|
            expect(window[:in_sample_start]).to eq(from_date)
          end
        end

        it 'handles date range too short for windows' do
          short_from = 10.days.ago.to_date
          short_to = Date.today

          walk_forward = described_class.new(
            instruments: instruments,
            from_date: short_from,
            to_date: short_to,
            in_sample_days: 90,
            out_of_sample_days: 30
          )

          windows = walk_forward.send(:generate_windows)

          expect(windows).to be_empty
        end
      end

      describe '#run_backtest' do
        before do
          allow(Backtesting::SwingBacktester).to receive(:call).and_return(
            {
              success: true,
              results: {
                total_return: 10.0,
                sharpe_ratio: 1.5
              }
            }
          )
        end

        it 'runs backtest for given date range' do
          result = walk_forward.send(:run_backtest,
            from_date: from_date,
            to_date: to_date,
            window_index: 0,
            period_type: 'in_sample')

          expect(result[:success]).to be true
          expect(Backtesting::SwingBacktester).to have_received(:call)
        end

        it 'handles failed backtest' do
          allow(Backtesting::SwingBacktester).to receive(:call).and_return(
            { success: false, error: 'Backtest failed' }
          )

          result = walk_forward.send(:run_backtest,
            from_date: from_date,
            to_date: to_date,
            window_index: 0,
            period_type: 'in_sample')

          expect(result[:success]).to be false
        end
      end

      describe '#aggregate_results' do
        let(:in_sample_results) do
          [
            { results: { total_return: 10.0, sharpe_ratio: 1.5 } },
            { results: { total_return: 15.0, sharpe_ratio: 1.8 } }
          ]
        end

        let(:out_of_sample_results) do
          [
            { results: { total_return: 8.0, sharpe_ratio: 1.2 } },
            { results: { total_return: 12.0, sharpe_ratio: 1.5 } }
          ]
        end

        it 'aggregates in-sample and out-of-sample results' do
          aggregated = walk_forward.send(:aggregate_results, in_sample_results, out_of_sample_results)

          expect(aggregated).to have_key(:in_sample)
          expect(aggregated).to have_key(:out_of_sample)
          expect(aggregated[:in_sample]).to have_key(:avg_total_return)
          expect(aggregated[:out_of_sample]).to have_key(:avg_total_return)
        end

        it 'handles empty results' do
          aggregated = walk_forward.send(:aggregate_results, [], [])

          expect(aggregated).to eq({})
        end
      end

      describe '#compare_in_sample_vs_out_of_sample' do
        let(:in_sample_results) do
          [
            { results: { total_return: 10.0, sharpe_ratio: 1.5 } }
          ]
        end

        let(:out_of_sample_results) do
          [
            { results: { total_return: 8.0, sharpe_ratio: 1.2 } }
          ]
        end

        it 'compares in-sample vs out-of-sample performance' do
          comparison = walk_forward.send(:compare_in_sample_vs_out_of_sample,
            in_sample_results, out_of_sample_results)

          expect(comparison).to be_present
        end

        it 'handles empty results' do
          comparison = walk_forward.send(:compare_in_sample_vs_out_of_sample, [], [])

          expect(comparison).to eq({})
        end
      end
    end
  end
end

