# frozen_string_literal: true

class AboutController < ApplicationController
  layout "dashboard"

  def index
    @dhan_profile = get_dhan_profile || { error: "Unable to fetch profile" }
    @dhan_expirations = check_dhan_expirations
    @telegram_status = get_telegram_info || { configured: false }

    # Calculate time remaining for display
    return unless @dhan_profile && !@dhan_profile[:error]

    @token_time_remaining = calculate_time_remaining(@dhan_profile[:token_validity])
    @data_time_remaining = calculate_time_remaining(@dhan_profile[:data_validity])
  end

  private

  def get_dhan_profile
    require "dhan_hq"
    profile = DhanHQ::Models::Profile.fetch
    return { error: "No profile data returned" } unless profile

    {
      client_id: profile.respond_to?(:dhan_client_id) ? profile.dhan_client_id : nil,
      token_validity: profile.respond_to?(:token_validity) ? profile.token_validity : nil,
      active_segment: profile.respond_to?(:active_segment) ? profile.active_segment : nil,
      ddpi: profile.respond_to?(:ddpi) ? profile.ddpi : nil,
      mtf: profile.respond_to?(:mtf) ? profile.mtf : nil,
      data_plan: profile.respond_to?(:data_plan) ? profile.data_plan : nil,
      data_validity: profile.respond_to?(:data_validity) ? profile.data_validity : nil,
    }
  rescue LoadError => e
    Rails.logger.error("[AboutController] DhanHQ gem not installed: #{e.message}")
    { error: "DhanHQ gem not installed" }
  rescue StandardError => e
    Rails.logger.error("[AboutController] Error fetching DhanHQ profile: #{e.message}")
    Rails.logger.error("[AboutController] Backtrace: #{e.backtrace.first(10).join("\n")}")
    { error: e.message }
  end

  def check_dhan_expirations
    profile = get_dhan_profile
    return [] if profile.nil? || profile[:error]

    warnings = []
    now = Time.current

    # Check token validity (tokens are always valid for 24 hours)
    if profile[:token_validity]
      token_expiry = parse_dhan_date(profile[:token_validity])
      if token_expiry
        if token_expiry < now
          warnings << { type: "token", message: "Token EXPIRED on #{profile[:token_validity]}", severity: "critical" }
        else
          hours_until_expiry = ((token_expiry - now) / 1.hour).to_f.round(1)
          if hours_until_expiry <= 2
            warnings << { type: "token",
                          message: "Token expires in #{hours_until_expiry} hours (#{profile[:token_validity]})", severity: "critical" }
          elsif hours_until_expiry <= 6
            warnings << { type: "token",
                          message: "Token expires in #{hours_until_expiry} hours (#{profile[:token_validity]})", severity: "warning" }
          end
        end
      end
    end

    # Check data validity
    if profile[:data_validity]
      data_expiry = parse_dhan_date(profile[:data_validity])
      if data_expiry
        if data_expiry < now
          warnings << { type: "data_plan", message: "Data plan EXPIRED on #{profile[:data_validity]}",
                        severity: "critical" }
        else
          days_until_expiry = ((data_expiry - now) / 1.day).to_i
          if days_until_expiry <= 7
            warnings << { type: "data_plan",
                          message: "Data plan expires in #{days_until_expiry} days (#{profile[:data_validity]})", severity: "warning" }
          end
        end
      end
    end

    warnings
  rescue StandardError => e
    Rails.logger.error("[AboutController] Error checking DhanHQ expirations: #{e.message}")
    []
  end

  def parse_dhan_date(date_string)
    return nil unless date_string.present?

    # Try parsing formats like "14/12/2025 19:08" or "2025-12-26 00:00:00.0"
    if date_string.match?(%r{\d{2}/\d{2}/\d{4}})
      # Format: "14/12/2025 19:08"
      parts = date_string.split
      date_part = parts[0]
      time_part = parts[1] || "00:00"
      day, month, year = date_part.split("/").map(&:to_i)
      hour, minute = time_part.split(":").map(&:to_i)
      Time.zone.local(year, month, day, hour, minute)
    elsif date_string.match?(/\d{4}-\d{2}-\d{2}/)
      # Format: "2025-12-26 00:00:00.0"
      Time.zone.parse(date_string)
    else
      nil
    end
  rescue StandardError
    nil
  end

  def get_telegram_info
    return { configured: false } unless TelegramNotifier.enabled?

    bot_token = ENV.fetch("TELEGRAM_BOT_TOKEN", nil)
    return { configured: false } unless bot_token.present?

    begin
      require "net/http"
      require "uri"
      uri = URI("https://api.telegram.org/bot#{bot_token}/getMe")
      response = Net::HTTP.get_response(uri)
      if response.code == "200"
        data = JSON.parse(response.body)
        if data["ok"]
          result = data["result"]
          {
            configured: true,
            bot_id: result["id"],
            bot_username: result["username"],
            bot_first_name: result["first_name"],
            bot_is_bot: result["is_bot"],
          }
        else
          { configured: true, error: data["description"] }
        end
      else
        { configured: true, error: "HTTP #{response.code}" }
      end
    rescue JSON::ParserError => e
      { configured: true, error: "Error parsing response: #{e.message}" }
    rescue StandardError => e
      { configured: true, error: e.message }
    end
  end

  def calculate_time_remaining(date_string)
    return nil unless date_string.present?

    expiry_time = parse_dhan_date(date_string)
    return nil unless expiry_time

    now = Time.current
    return { expired: true, message: "Expired" } if expiry_time < now

    seconds_remaining = (expiry_time - now).to_i
    days = seconds_remaining / 1.day
    hours = (seconds_remaining % 1.day) / 1.hour
    minutes = (seconds_remaining % 1.hour) / 1.minute

    if days > 0
      { expired: false, message: "#{days} day#{'s' if days != 1}, #{hours} hour#{'s' if hours != 1}" }
    elsif hours > 0
      { expired: false, message: "#{hours} hour#{'s' if hours != 1}, #{minutes} minute#{'s' if minutes != 1}" }
    else
      { expired: false, message: "#{minutes} minute#{'s' if minutes != 1}" }
    end
  end
end
