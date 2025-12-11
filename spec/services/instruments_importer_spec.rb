# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstrumentsImporter do
  let(:csv_url) { 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv' }
  let(:cache_path) { Rails.root.join('tmp/dhan_scrip_master.csv') }
  let(:sample_csv) do
    <<~CSV
      Security Id,Exchange,Segment,Instrument Type,Symbol Name,Series,ISIN,Underlying Security Id,Underlying Symbol,Expiry Date,Strike Price,Option Type,Exchange Segment
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

        result = InstrumentsImporter.import_from_url

        # Should only import instruments in universe
        expect(Instrument.pluck(:symbol_name)).to contain_exactly('RELIANCE', 'TCS')

        # Cleanup
        File.delete(universe_file) if File.exist?(universe_file)
      end

      it 'skips derivatives' do
        csv_with_derivatives = sample_csv + "\n99999,NSE,D,FUTSTK,RELIANCE FUT,XX,INE467B01032,11536,RELIANCE,2025-12-31,,,NSE_FNO"
        allow(InstrumentsImporter).to receive(:fetch_csv_with_cache).and_return(csv_with_derivatives)

        InstrumentsImporter.import_from_url

        # Should not import futures
        expect(Instrument.where(instrument_type: 'FUTSTK').count).to eq(0)
      end

      it 'only imports NSE and BSE instruments' do
        csv_with_multiple = sample_csv + "\n88888,MCX,M,COMMODITY,GOLD,XX,INE467B01033,,,2025-12-31,,,MCX_COMM"
        allow(InstrumentsImporter).to receive(:fetch_csv_with_cache).and_return(csv_with_multiple)

        InstrumentsImporter.import_from_url

        # Should not import MCX instruments
        expect(Instrument.where(exchange: 'MCX').count).to eq(0)
      end
    end

    context 'with CSV caching' do
      it 'uses cached CSV if available and fresh' do
        # Create a fresh cache file
        FileUtils.mkdir_p(cache_path.dirname)
        File.write(cache_path, sample_csv)
        FileUtils.touch(cache_path, mtime: Time.current)

        expect(URI).not_to receive(:open)
        allow(InstrumentsImporter).to receive(:import_from_csv).and_return({ instrument_total: 0 })

        InstrumentsImporter.import_from_url
      end

      it 'fetches new CSV if cache is stale' do
        # Create a stale cache file
        FileUtils.mkdir_p(cache_path.dirname)
        File.write(cache_path, sample_csv)
        FileUtils.touch(cache_path, mtime: 2.days.ago)

        allow(URI).to receive(:open).and_return(StringIO.new(sample_csv))
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
      expect(reliance.exchange).to eq('NSE')
      expect(reliance.segment).to eq('E')
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

      result = importer.import_from_csv(sample_csv)

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
      allow(URI).to receive(:open).and_return(StringIO.new(sample_csv))

      result = InstrumentsImporter.fetch_csv_with_cache

      expect(result).to eq(sample_csv)
      expect(URI).to have_received(:open).with(csv_url, any_args)
    end

    it 'saves CSV to cache file' do
      allow(URI).to receive(:open).and_return(StringIO.new(sample_csv))

      InstrumentsImporter.fetch_csv_with_cache

      expect(cache_path).to exist
      expect(File.read(cache_path)).to eq(sample_csv)
    end

    it 'returns cached CSV if fresh' do
      # Create cache
      FileUtils.mkdir_p(cache_path.dirname)
      File.write(cache_path, sample_csv)
      FileUtils.touch(cache_path, mtime: Time.current)

      expect(URI).not_to receive(:open)

      result = InstrumentsImporter.fetch_csv_with_cache
      expect(result).to eq(sample_csv)
    end

    it 'refetches if cache is stale' do
      # Create stale cache
      FileUtils.mkdir_p(cache_path.dirname)
      File.write(cache_path, 'old data')
      FileUtils.touch(cache_path, mtime: 2.days.ago)

      allow(URI).to receive(:open).and_return(StringIO.new(sample_csv))

      result = InstrumentsImporter.fetch_csv_with_cache

      expect(result).to eq(sample_csv)
      expect(File.read(cache_path)).to eq(sample_csv)
    end
  end
end

