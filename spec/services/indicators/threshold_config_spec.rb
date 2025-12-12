# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::ThresholdConfig, type: :service do
  describe '.get_preset' do
    it 'returns loose preset' do
      preset = described_class.get_preset(:loose)

      expect(preset[:adx][:min_strength]).to eq(10)
      expect(preset[:rsi][:oversold]).to eq(40)
    end

    it 'returns moderate preset by default' do
      preset = described_class.get_preset

      expect(preset[:adx][:min_strength]).to eq(15)
      expect(preset[:rsi][:oversold]).to eq(35)
    end

    it 'returns tight preset' do
      preset = described_class.get_preset(:tight)

      expect(preset[:adx][:min_strength]).to eq(25)
      expect(preset[:rsi][:oversold]).to eq(25)
    end

    it 'returns production preset' do
      preset = described_class.get_preset(:production)

      expect(preset[:adx][:min_strength]).to eq(20)
      expect(preset[:rsi][:oversold]).to eq(30)
    end

    it 'returns moderate for invalid preset' do
      preset = described_class.get_preset(:invalid)

      expect(preset[:adx][:min_strength]).to eq(15)
    end
  end

  describe '.current_preset' do
    context 'when algo.yml has preset' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          signals: { indicator_preset: 'tight' }
        )
      end

      it 'returns preset from algo.yml' do
        preset_name = described_class.current_preset

        expect(preset_name).to eq(:tight)
      end
    end

    context 'when ENV has preset' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({})
        allow(ENV).to receive(:[]).with('INDICATOR_PRESET').and_return('loose')
      end

      it 'returns preset from ENV' do
        preset_name = described_class.current_preset

        expect(preset_name).to eq(:loose)
      end
    end

    context 'when no preset configured' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({})
        allow(ENV).to receive(:[]).with('INDICATOR_PRESET').and_return(nil)
      end

      it 'returns moderate as default' do
        preset_name = described_class.current_preset

        expect(preset_name).to eq(:moderate)
      end
    end
  end

  describe '.for_indicator' do
    it 'returns thresholds for specific indicator' do
      thresholds = described_class.for_indicator(:rsi, :loose)

      expect(thresholds[:oversold]).to eq(40)
      expect(thresholds[:overbought]).to eq(60)
    end

    it 'uses current preset when not specified' do
      allow(described_class).to receive(:current_preset).and_return(:tight)

      thresholds = described_class.for_indicator(:rsi)

      expect(thresholds[:oversold]).to eq(25)
    end
  end

  describe '.merge_with_thresholds' do
    it 'merges base config with thresholds' do
      base_config = { period: 21 }
      result = described_class.merge_with_thresholds(:rsi, base_config, :loose)

      expect(result[:period]).to eq(21)
      expect(result[:oversold]).to eq(40)
    end

    it 'allows base config to override thresholds' do
      base_config = { oversold: 35 }
      result = described_class.merge_with_thresholds(:rsi, base_config, :loose)

      expect(result[:oversold]).to eq(35)
    end
  end

  describe '.available_presets' do
    it 'returns all preset names' do
      presets = described_class.available_presets

      expect(presets).to include(:loose, :moderate, :tight, :production)
    end
  end

  describe '.preset_exists?' do
    it 'returns true for valid preset' do
      expect(described_class.preset_exists?(:moderate)).to be true
    end

    it 'returns false for invalid preset' do
      expect(described_class.preset_exists?(:invalid)).to be false
    end
  end
end

