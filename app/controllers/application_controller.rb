# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  layout :determine_layout

  before_action :set_trading_mode

  helper_method :current_trading_mode

  private

  def determine_layout
    if controller_name == "dashboard"
      "dashboard"
    else
      "application"
    end
  end

  def set_trading_mode
    # Initialize session mode if not set (default to 'live')
    session[:trading_mode] ||= "live"
  end

  def current_trading_mode
    session[:trading_mode] || "live"
  end
end
