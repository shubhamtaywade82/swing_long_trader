# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstrumentsImporter do
  let(:csv_url) { 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv' }
  let(:cache_path) { Rails.root.join('tmp/dhan_scrip_master.csv') }
  let(:sample_csv) do
    <<~CSV
      SECURITY_ID,EXCH_ID,SEGMENT,INSTRUMENT_TYPE,SYMBOL_NAME,SERIES,ISIN,UNDERLYING_SECURITY_ID,UNDERLYING_SYMBOL,SM_EXPIRY_DATE,STRIKE_PRICE,OPTION_TYPE,EXCH_SEGMENT
      11536,NSE,E,EQUITY,RELIANCE,EQ,INE467B01029,,,2025-12-31,,,NSE_EQ
      11537,NSE,E,EQUITY,TCS,EQ,INE467B01030,,,2025-12-31,,,NSE_EQ
      9999,NSE,I,INDEX,NIFTY 50,XX,INE467B01031,,,2025-12-31,,,IDX_I
    CSV
  end

  describe '.import_from_url', :vcr do
    context 'with valid CSV data' do
      before do
        # Clean up any existing instruments
        Instrument.delete_all
        Setting.delete_all
      end

      it 'imports instruments from CSV' do
        # Mock the CSV fetch to use sample data
        allow(InstrumentsImporter).to receive(:fetch_csv_with_cache).and_return(sample_csv)

        result = InstrumentsImporter.import_from_url

        expect(result).to be_a(Hash)
        expect(result[:instrument_total]).to be > 0
        expect(result[:success]).to be true
      end

      it 'creates instruments in the database' do
        allow(InstrumentsImporter).to receive(:fetch_csv_with_cache).and_return(sample_csv)

        expect do
          InstrumentsImporter.import_from_url
        end.to change(Instrument, :count).by_at_least(2)
      end

      it 'records import statistics in settings' do
        allow(InstrumentsImporter).to receive(:fetch_csv_with_cache).and_return(sample_csv)

        InstrumentsImporter.import_from_url

        expect(Setting.fetch('instruments.last_imported_at')).to be_present
        expect(Setting.fetch('instruments.instrument_total')).to be_present
      end

      it 'filters instruments by universe if master_universe.yml exists' do
        # Create universe file
        universe_file = Rails.root.join('config/universe/master_universe.yml')
        FileUtils.mkdir_p(universe_file.dirname)
        File.write(universe_file, YAML.dump(['RELIANCE', 'TCS']))

        allow(InstrumentsImporter).to receive(:fetch_csv_with_cache).and_return(sample_csv)

        _result = InstrumentsImporter.import_from_url

        # Should only import instruments in universe
        expect(Instrument.pluck(:symbol_name)).to contain_exactly('RELIANCE', 'TCS')

        # Cleanup
        File.delete(universe_file) if File.exist?(universe_file)
      end

      it 'skips derivatives' do
        csv_with_derivatives = sample_csv + "\n99999,NSE,D,FUTSTK,RELIANCE FUT,XX,INE467B01032,11536,RELIANCE,2025-12-31,,,NSE_FNO"
        allow(InstrumentsImporter).to receive(:fetch_csv_with_cache).and_return(csv_with_derivatives)

        InstrumentsImporter.import_from_url

        # Should not import futures (segment D is skipped)
        expect(Instrument.where(segment: 'D').count).to eq(0)
      end

      it 'only imports NSE and BSE instruments' do
        csv_with_multiple = sample_csv + "\n88888,MCX,M,COMMODITY,GOLD,XX,INE467B01033,,,2025-12-31,,,MCX_COMM"
        allow(InstrumentsImporter).to receive(:fetch_csv_with_cache).and_return(csv_with_multiple)

        InstrumentsImporter.import_from_url

        # Should not import MCX instruments (only NSE and BSE are valid)
        # Note: exchange is stored as enum key (lowercase) in database
        expect(Instrument.where(exchange: 'mcx').count).to eq(0)
        expect(Instrument.pluck(:exchange).uniq).to contain_exactly('nse')
      end
    end

    context 'with CSV caching' do
      it 'uses cached CSV if available and fresh' do
        # Create a fresh cache file
        FileUtils.mkdir_p(cache_path.dirname)
        File.write(cache_path, sample_csv)
        FileUtils.touch(cache_path, mtime: Time.current.to_time)

        expect(URI).not_to receive(:open)
        allow(InstrumentsImporter).to receive(:import_from_csv).and_return({ instrument_total: 0 })

        InstrumentsImporter.import_from_url
      end

      it 'fetches new CSV if cache is stale' do
        # Create a stale cache file
        FileUtils.mkdir_p(cache_path.dirname)
        File.write(cache_path, sample_csv)
        FileUtils.touch(cache_path, mtime: 2.days.ago.to_time)

        allow(URI).to receive(:open).and_yield(StringIO.new(sample_csv))
        allow(InstrumentsImporter).to receive(:import_from_csv).and_return({ instrument_total: 0 })

        InstrumentsImporter.import_from_url

        expect(URI).to have_received(:open)
      end
    end

    context 'with errors' do
      it 'handles network errors gracefully' do
        allow(InstrumentsImporter).to receive(:fetch_csv_with_cache).and_raise(StandardError.new('Network error'))

        expect do
          InstrumentsImporter.import_from_url
        end.to raise_error(StandardError)
      end

      it 'uses cached file as fallback on network error' do
        # Create cache file
        FileUtils.mkdir_p(cache_path.dirname)
        File.write(cache_path, sample_csv)

        allow(URI).to receive(:open).and_raise(StandardError.new('Network error'))
        allow(InstrumentsImporter).to receive(:import_from_csv).and_return({ instrument_total: 0 })

        # Should not raise error if cache exists
        expect do
          InstrumentsImporter.import_from_url
        end.not_to raise_error
      end
    end
  end

  describe '.import_from_csv' do
    let(:importer) { InstrumentsImporter }

    before do
      Instrument.delete_all
    end

    it 'parses CSV and creates instruments' do
      result = importer.import_from_csv(sample_csv)

      expect(result[:instrument_total]).to eq(3)
      expect(Instrument.count).to eq(3)
    end

    it 'creates instruments with correct attributes' do
      importer.import_from_csv(sample_csv)

      reliance = Instrument.find_by(symbol_name: 'RELIANCE')
      expect(reliance).to be_present
      # Note: exchange and segment are stored as enum keys in database
      expect(reliance.exchange).to eq('nse')
      expect(reliance.segment).to eq('equity')
      expect(reliance.instrument_type).to eq('EQUITY')
      expect(reliance.security_id).to eq('11536')
    end

    it 'handles duplicate security_ids (upsert)' do
      # Import once
      importer.import_from_csv(sample_csv)
      initial_count = Instrument.count

      # Import again with same data
      importer.import_from_csv(sample_csv)

      # Should not create duplicates
      expect(Instrument.count).to eq(initial_count)
    end

    it 'updates existing instruments on reimport' do
      # Create existing instrument
      create(:instrument, security_id: '11536', symbol_name: 'RELIANCE_OLD')

      importer.import_from_csv(sample_csv)

      reliance = Instrument.find_by(security_id: '11536')
      expect(reliance.symbol_name).to eq('RELIANCE')
    end

    it 'filters by universe whitelist' do
      # Create universe file
      universe_file = Rails.root.join('config/universe/master_universe.yml')
      FileUtils.mkdir_p(universe_file.dirname)
      File.write(universe_file, YAML.dump(['RELIANCE']))

      _result = importer.import_from_csv(sample_csv)

      # Should only import RELIANCE
      expect(Instrument.count).to eq(1)
      expect(Instrument.first.symbol_name).to eq('RELIANCE')

      # Cleanup
      File.delete(universe_file) if File.exist?(universe_file)
    end

    it 'skips invalid rows gracefully' do
      invalid_csv = sample_csv + "\ninvalid,row,data"
      result = importer.import_from_csv(invalid_csv)

      # Should still import valid rows
      expect(result[:instrument_total]).to eq(3)
    end
  end

  describe '.fetch_csv_with_cache' do
    before do
      FileUtils.rm_f(cache_path) if cache_path.exist?
    end

    after do
      FileUtils.rm_f(cache_path) if cache_path.exist?
    end

    it 'fetches CSV from URL' do
      allow(URI).to receive(:open).and_yield(StringIO.new(sample_csv))

      result = InstrumentsImporter.send(:fetch_csv_with_cache)

      expect(result).to eq(sample_csv)
      expect(URI).to have_received(:open).with(csv_url, any_args)
    end

    it 'saves CSV to cache file' do
      allow(URI).to receive(:open).and_yield(StringIO.new(sample_csv))

      InstrumentsImporter.send(:fetch_csv_with_cache)

      expect(cache_path).to exist
      expect(File.read(cache_path)).to eq(sample_csv)
    end

    it 'returns cached CSV if fresh' do
      # Create cache
      FileUtils.mkdir_p(cache_path.dirname)
      File.write(cache_path, sample_csv)
      FileUtils.touch(cache_path, mtime: Time.current.to_time)

      expect(URI).not_to receive(:open)

      result = InstrumentsImporter.send(:fetch_csv_with_cache)
      expect(result).to eq(sample_csv)
    end

    it 'refetches if cache is stale' do
      # Create stale cache
      FileUtils.mkdir_p(cache_path.dirname)
      File.write(cache_path, 'old data')
      FileUtils.touch(cache_path, mtime: 2.days.ago.to_time)

      allow(URI).to receive(:open).and_yield(StringIO.new(sample_csv))

      result = InstrumentsImporter.send(:fetch_csv_with_cache)

      expect(result).to eq(sample_csv)
      expect(File.read(cache_path)).to eq(sample_csv)
    end

    it 'falls back to cached CSV on network error if cache exists' do
      # Create cache
      FileUtils.mkdir_p(cache_path.dirname)
      File.write(cache_path, sample_csv)

      allow(URI).to receive(:open).and_raise(StandardError.new('Network error'))

      result = InstrumentsImporter.send(:fetch_csv_with_cache)

      expect(result).to eq(sample_csv)
    end

    it 'raises error if network fails and no cache exists' do
      FileUtils.rm_f(cache_path) if cache_path.exist?

      allow(URI).to receive(:open).and_raise(StandardError.new('Network error'))

      expect do
        InstrumentsImporter.send(:fetch_csv_with_cache)
      end.to raise_error(StandardError, 'Network error')
    end
  end

  describe '.build_batches' do
    it 'filters by exchange' do
      csv_with_multiple = sample_csv + "\n88888,MCX,M,COMMODITY,GOLD,XX,INE467B01033,,,2025-12-31,,,MCX_COMM"
      batches = InstrumentsImporter.send(:build_batches, csv_with_multiple)

      # Should only include NSE/BSE instruments
      expect(batches.size).to eq(3) # RELIANCE, TCS, NIFTY 50
    end

    it 'filters by segment (skips derivatives)' do
      csv_with_derivatives = sample_csv + "\n99999,NSE,D,FUTSTK,RELIANCE FUT,XX,INE467B01032,11536,RELIANCE,2025-12-31,,,NSE_FNO"
      batches = InstrumentsImporter.send(:build_batches, csv_with_derivatives)

      expect(batches.size).to eq(3) # Should not include futures
    end

    it 'handles symbols with suffixes in universe matching' do
      universe_file = Rails.root.join('config/universe/master_universe.yml')
      FileUtils.mkdir_p(universe_file.dirname)
      File.write(universe_file, YAML.dump(['RELIANCE']))

      csv_with_suffix = sample_csv.gsub('RELIANCE', 'RELIANCE-EQ')
      batches = InstrumentsImporter.send(:build_batches, csv_with_suffix)

      # Should match RELIANCE-EQ to RELIANCE in universe
      expect(batches.size).to eq(1)
      expect(batches.first[:symbol_name]).to eq('RELIANCE-EQ')

      File.delete(universe_file) if File.exist?(universe_file)
    end

    it 'handles empty CSV' do
      batches = InstrumentsImporter.send(:build_batches, '')
      expect(batches).to eq([])
    end

    it 'handles CSV with only headers' do
      header_only = "SECURITY_ID,EXCH_ID,SEGMENT,INSTRUMENT_TYPE,SYMBOL_NAME\n"
      batches = InstrumentsImporter.send(:build_batches, header_only)
      expect(batches).to eq([])
    end
  end

  describe '.build_attrs' do
    it 'builds correct attributes from CSV row' do
      row = CSV.parse(sample_csv, headers: true).first
      attrs = InstrumentsImporter.send(:build_attrs, row)

      expect(attrs[:security_id]).to eq('11536')
      expect(attrs[:symbol_name]).to eq('RELIANCE')
      expect(attrs[:instrument_type]).to eq('EQUITY')
    end
  end

  describe '.import_instruments!' do
    it 'upserts instruments in batches' do
      batches = InstrumentsImporter.send(:build_batches, sample_csv)
      result = InstrumentsImporter.send(:import_instruments!, batches)

      expect(result).to be_present
      expect(result.ids.size).to eq(3)
    end

    it 'handles empty batches' do
      result = InstrumentsImporter.send(:import_instruments!, [])

      expect(result).to be_nil
    end
  end

  describe '.record_success!' do
    it 'records import statistics' do
      summary = {
        instrument_total: 100,
        instrument_upserts: 50,
        finished_at: Time.current,
        duration: 5.5
      }
      InstrumentsImporter.send(:record_success!, summary)

      expect(Setting.fetch('instruments.last_imported_at')).to be_present
      expect(Setting.fetch('instruments.instrument_total')).to eq(100)
      expect(Setting.fetch('instruments.last_instrument_rows')).to eq(summary[:instrument_rows])
      expect(Setting.fetch('instruments.last_instrument_upserts')).to eq(50)
    end
  end

  describe '.load_universe_symbols' do
    it 'loads symbols from universe file' do
      universe_file = Rails.root.join('config/universe/master_universe.yml')
      FileUtils.mkdir_p(universe_file.dirname)
      File.write(universe_file, YAML.dump(['RELIANCE', 'TCS', 'INFY']))

      symbols = InstrumentsImporter.send(:load_universe_symbols)

      expect(symbols).to be_a(Set)
      expect(symbols).to include('RELIANCE', 'TCS', 'INFY')

      File.delete(universe_file) if File.exist?(universe_file)
    end

    it 'returns empty set if universe file does not exist' do
      symbols = InstrumentsImporter.send(:load_universe_symbols)

      expect(symbols).to be_a(Set)
      expect(symbols).to be_empty
    end

    it 'handles invalid YAML gracefully' do
      universe_file = Rails.root.join('config/universe/master_universe.yml')
      FileUtils.mkdir_p(universe_file.dirname)
      File.write(universe_file, 'invalid: yaml: content: [unclosed')

      allow(Rails.logger).to receive(:warn)

      symbols = InstrumentsImporter.send(:load_universe_symbols)

      expect(symbols).to be_a(Set)
      expect(symbols).to be_empty
      expect(Rails.logger).to have_received(:warn).with(/Failed to load universe/)

      File.delete(universe_file) if File.exist?(universe_file)
    end

    it 'normalizes symbols to uppercase' do
      universe_file = Rails.root.join('config/universe/master_universe.yml')
      FileUtils.mkdir_p(universe_file.dirname)
      File.write(universe_file, YAML.dump(['reliance', 'tcs']))

      symbols = InstrumentsImporter.send(:load_universe_symbols)

      expect(symbols).to include('RELIANCE', 'TCS')

      File.delete(universe_file) if File.exist?(universe_file)
    end
  end

  describe '.build_attrs' do
    it 'builds attributes with all fields' do
      row = CSV.parse(sample_csv, headers: true).first
      attrs = InstrumentsImporter.send(:build_attrs, row)

      expect(attrs[:security_id]).to eq('11536')
      expect(attrs[:symbol_name]).to eq('RELIANCE')
      expect(attrs[:exchange]).to eq('NSE')
      expect(attrs[:segment]).to eq('E')
      expect(attrs[:instrument_type]).to eq('EQUITY')
      expect(attrs[:isin]).to eq('INE467B01029')
      expect(attrs[:created_at]).to be_present
      expect(attrs[:updated_at]).to be_present
    end

    it 'handles nil values gracefully' do
      row = CSV.parse(sample_csv, headers: true).first
      row['LOT_SIZE'] = nil
      row['STRIKE_PRICE'] = nil

      attrs = InstrumentsImporter.send(:build_attrs, row)

      expect(attrs[:lot_size]).to be_nil
      expect(attrs[:strike_price]).to be_nil
    end

    it 'converts numeric fields correctly' do
      row = CSV.parse(sample_csv, headers: true).first
      row['LOT_SIZE'] = '50'
      row['STRIKE_PRICE'] = '2500.50'

      attrs = InstrumentsImporter.send(:build_attrs, row)

      expect(attrs[:lot_size]).to eq(50)
      expect(attrs[:strike_price]).to eq(2500.50)
    end
  end

  describe '.safe_date' do
    it 'parses valid date strings' do
      date = InstrumentsImporter.send(:safe_date, '2025-12-31')
      expect(date).to eq(Date.parse('2025-12-31'))
    end

    it 'returns nil for invalid date strings' do
      date = InstrumentsImporter.send(:safe_date, 'invalid-date')
      expect(date).to be_nil
    end

    it 'returns nil for nil input' do
      date = InstrumentsImporter.send(:safe_date, nil)
      expect(date).to be_nil
    end
  end

  describe '.map_segment' do
    it 'maps segment codes correctly' do
      expect(InstrumentsImporter.send(:map_segment, 'I')).to eq('index')
      expect(InstrumentsImporter.send(:map_segment, 'E')).to eq('equity')
      expect(InstrumentsImporter.send(:map_segment, 'C')).to eq('currency')
      expect(InstrumentsImporter.send(:map_segment, 'D')).to eq('derivatives')
      expect(InstrumentsImporter.send(:map_segment, 'M')).to eq('commodity')
    end

    it 'returns lowercase for unknown codes' do
      expect(InstrumentsImporter.send(:map_segment, 'X')).to eq('x')
    end
  end

  describe '.import_instruments!' do
    it 'deduplicates rows by composite key' do
      rows = [
        { security_id: '11536', exchange: 'NSE', segment: 'E', symbol_name: 'RELIANCE' },
        { security_id: '11536', exchange: 'NSE', segment: 'E', symbol_name: 'RELIANCE_UPDATED' }
      ]

      result = InstrumentsImporter.send(:import_instruments!, rows)

      expect(result.ids.size).to eq(1)
      # Last occurrence should be kept
      instrument = Instrument.find_by(security_id: '11536')
      expect(instrument.symbol_name).to eq('RELIANCE_UPDATED')
    end

    it 'handles large batches' do
      rows = (1..2000).map do |i|
        { security_id: i.to_s, exchange: 'NSE', segment: 'E', symbol_name: "STOCK#{i}" }
      end

      result = InstrumentsImporter.send(:import_instruments!, rows)

      expect(result.ids.size).to eq(2000)
    end
  end
end

