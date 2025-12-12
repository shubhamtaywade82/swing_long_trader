# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Screeners::AIRankerJob, type: :job do
  let(:candidates) do
    [
      { instrument_id: 1, symbol: 'RELIANCE', score: 85 },
      { instrument_id: 2, symbol: 'TCS', score: 75 }
    ]
  end

  describe '#perform' do
    context 'when ranking succeeds' do
      before do
        allow(Screeners::AIRanker).to receive(:call).and_return(candidates)
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'calls AIRanker service' do
        result = described_class.new.perform(candidates)

        expect(result).to eq(candidates)
        expect(Screeners::AIRanker).to have_received(:call).with(candidates: candidates, limit: nil)
      end

      it 'logs success message' do
        allow(Rails.logger).to receive(:info)

        described_class.new.perform(candidates)

        expect(Rails.logger).to have_received(:info)
      end
    end

    context 'when limit is provided' do
      before do
        allow(Screeners::AIRanker).to receive(:call).and_return(candidates.first(1))
      end

      it 'passes limit to service' do
        described_class.new.perform(candidates, limit: 1)

        expect(Screeners::AIRanker).to have_received(:call).with(candidates: candidates, limit: 1)
      end
    end

    context 'when ranking fails' do
      before do
        allow(Screeners::AIRanker).to receive(:call).and_raise(StandardError, 'Ranking error')
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'sends error alert and raises' do
        expect do
          described_class.new.perform(candidates)
        end.to raise_error(StandardError, 'Ranking error')

        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end
    end
  end
end

