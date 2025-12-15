# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  include TradingModeHelper
  include SolidQueueHelper
  include ErrorHandler

  # CSRF protection - skip for JSON API requests if needed
  protect_from_forgery with: :exception
  skip_before_action :verify_authenticity_token, if: :json_request?

  layout :determine_layout

  before_action :set_trading_mode
  # TODO: Add authentication when user system is implemented
  # before_action :authenticate_user!
  # before_action :authorize_user!

  helper_method :current_trading_mode

  private

  def json_request?
    request.format.json?
  end

  def determine_layout
    # Use dashboard layout for dashboard-related controllers
    if %w[dashboard positions portfolios signals orders monitoring screeners ai_evaluations
          about].include?(controller_name)
      "dashboard"
    else
      "application"
    end
  end

  def set_trading_mode
    # Initialize session mode if not set (default to 'live')
    # Validate session value to prevent injection
    session[:trading_mode] = "live" unless %w[live paper].include?(session[:trading_mode])
  end

  # Placeholder for future authentication
  # def authenticate_user!
  #   # Implement authentication logic
  #   # For now, allow all requests
  # end

  # Placeholder for future authorization
  # def authorize_user!
  #   # Implement authorization logic
  #   # For now, allow all requests
  # end
end
