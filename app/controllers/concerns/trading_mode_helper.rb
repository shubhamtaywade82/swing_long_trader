# frozen_string_literal: true

module TradingModeHelper
  extend ActiveSupport::Concern

  included do
    helper_method :current_trading_mode
  end

  def toggle_trading_mode
    current_mode = session[:trading_mode] || "live"
    new_mode = current_mode == "live" ? "paper" : "live"
    session[:trading_mode] = new_mode

    Rails.logger.info("[TradingModeHelper] Trading mode toggled: #{current_mode} -> #{new_mode}")

    respond_to do |format|
      format.json { render json: { mode: new_mode, message: "Switched to #{new_mode.upcase} mode" } }
      format.html { redirect_to request.referer || root_path }
    end
  end

  private

  def current_trading_mode
    session[:trading_mode] || "live"
  end
end
