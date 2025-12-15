# frozen_string_literal: true

module ErrorHandler
  extend ActiveSupport::Concern

  included do
    rescue_from StandardError, with: :handle_standard_error
    rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
  end

  private

  def handle_standard_error(exception)
    Rails.logger.error("[#{self.class.name}] #{exception.class}: #{exception.message}")
    Rails.logger.error(exception.backtrace.first(10).join("\n"))

    respond_to do |format|
      format.json do
        render json: {
          error: "Internal server error",
          message: Rails.env.development? ? exception.message : nil,
        }, status: :internal_server_error
      end
      format.html { redirect_to root_path, alert: "An error occurred. Please try again." }
    end
  end

  def handle_not_found(exception)
    Rails.logger.warn("[#{self.class.name}] Record not found: #{exception.message}")

    respond_to do |format|
      format.json { render json: { error: "Resource not found" }, status: :not_found }
      format.html { redirect_to root_path, alert: "Resource not found" }
    end
  end

  def handle_parameter_missing(exception)
    Rails.logger.warn("[#{self.class.name}] Missing parameter: #{exception.message}")

    respond_to do |format|
      format.json { render json: { error: "Missing required parameter: #{exception.param}" }, status: :unprocessable_entity }
      format.html { redirect_to request.referer || root_path, alert: "Missing required parameter" }
    end
  end
end
