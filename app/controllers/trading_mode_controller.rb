# frozen_string_literal: true

class TradingModeController < ApplicationController
  include TradingModeHelper

  def toggle
    toggle_trading_mode
  end
end
