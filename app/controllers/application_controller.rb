# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  include TradingModeHelper
  include SolidQueueHelper

  layout :determine_layout

  before_action :set_trading_mode

  helper_method :current_trading_mode

  private

  def determine_layout
    # Use dashboard layout for dashboard-related controllers
    if %w[dashboard positions portfolios signals orders monitoring screeners ai_evaluations].include?(controller_name)
      "dashboard"
    else
      "application"
    end
  end

  def set_trading_mode
    # Initialize session mode if not set (default to 'live')
    session[:trading_mode] ||= "live"
  end
end
