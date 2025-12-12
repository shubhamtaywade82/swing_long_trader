# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaperTrading::ExitMonitorJob, type: :job do
  let(:portfolio) { create(:paper_portfolio) }

  describe '#perform' do
    context 'when paper trading is enabled' do
      before do
        allow(Rails.configuration.x.paper_trading).to receive(:enabled).and_return(true)
        allow(PaperTrading::Portfolio).to receive(:find_or_create_default).and_return(portfolio)
        allow(PaperTrading::Simulator).to receive(:check_exits).and_return(
          { checked: 5, exited: 2 }
        )
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'checks exit conditions' do
        result = described_class.new.perform

        expect(result[:checked]).to eq(5)
        expect(result[:exited]).to eq(2)
        expect(PaperTrading::Simulator).to have_received(:check_exits).with(portfolio: portfolio)
      end

      context 'when portfolio_id is provided' do
        it 'uses specified portfolio' do
          described_class.new.perform(portfolio_id: portfolio.id)

          expect(PaperTrading::Simulator).to have_received(:check_exits).with(portfolio: portfolio)
        end
      end
    end

    context 'when paper trading is disabled' do
      before do
        allow(Rails.configuration.x.paper_trading).to receive(:enabled).and_return(false)
      end

      it 'returns early' do
        result = described_class.new.perform

        expect(result).to be_nil
        expect(PaperTrading::Simulator).not_to have_received(:check_exits)
      end
    end

    context 'when portfolio is not found' do
      before do
        allow(Rails.configuration.x.paper_trading).to receive(:enabled).and_return(true)
        allow(PaperPortfolio).to receive(:find_by).and_return(nil)
        allow(PaperTrading::Portfolio).to receive(:find_or_create_default).and_return(nil)
      end

      it 'returns early' do
        result = described_class.new.perform(portfolio_id: 99999)

        expect(result).to be_nil
      end
    end

    context 'when job fails' do
      before do
        allow(Rails.configuration.x.paper_trading).to receive(:enabled).and_return(true)
        allow(PaperTrading::Portfolio).to receive(:find_or_create_default).and_raise(StandardError, 'Error')
        allow(Telegram::Notifier).to receive(:send_error_alert)
      end

      it 'sends error alert and raises' do
        expect do
          described_class.new.perform
        end.to raise_error(StandardError, 'Error')

        expect(Telegram::Notifier).to have_received(:send_error_alert)
      end
    end
  end
end

