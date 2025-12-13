# frozen_string_literal: true

class DashboardChannel < ApplicationCable::Channel
  def subscribed
    stream_from "dashboard_updates"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
