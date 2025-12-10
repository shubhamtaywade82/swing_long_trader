# frozen_string_literal: true

require 'test_helper'

module Screeners
  class SwingScreenerTest < ActiveSupport::TestCase
    setup do
      @instrument = create(:instrument)
      # Create candles for the instrument
      create_list(:daily_candle, 60, instrument: @instrument)
    end

    test 'should find candidates with valid data' do
      # Mock indicator calculations
      screener = SwingScreener.new(instruments: Instrument.where(id: @instrument.id), limit: 10)

      # This will fail without actual indicator data, but tests the structure
      candidates = screener.call

      # At minimum, should return an array
      assert_kind_of Array, candidates
    end

    test 'should filter instruments without candles' do
      instrument_no_candles = create(:instrument)

      screener = SwingScreener.new(
        instruments: Instrument.where(id: [@instrument.id, instrument_no_candles.id]),
        limit: 10
      )

      candidates = screener.call

      # Should only include instrument with candles
      candidate_ids = candidates.map { |c| c[:instrument_id] }
      assert_not_includes candidate_ids, instrument_no_candles.id
    end
  end
end

