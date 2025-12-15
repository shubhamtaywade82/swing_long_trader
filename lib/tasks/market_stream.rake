# frozen_string_literal: true

namespace :market do
  desc "Start real-time LTP streaming service (WebSocket -> Redis)"
  task start_stream: :environment do
    Rails.logger.info("[MarketStream] Starting LTP streaming service...")

    # Load instruments from active screener
    service = MarketData::StreamingService.new

    # Set up signal handlers for graceful shutdown
    trap("INT") do
      Rails.logger.info("[MarketStream] Received INT signal, shutting down...")
      service.stop
      exit(0)
    end

    trap("TERM") do
      Rails.logger.info("[MarketStream] Received TERM signal, shutting down...")
      service.stop
      exit(0)
    end

    # Start the service (blocks until market closes or stopped)
    result = service.start

    if result[:success]
      Rails.logger.info("[MarketStream] Streaming service stopped gracefully")
    else
      Rails.logger.error("[MarketStream] Streaming service failed: #{result[:error]}")
      exit(1)
    end
  end

  desc "Stop real-time LTP streaming service"
  task stop_stream: :environment do
    Rails.logger.info("[MarketStream] Stopping LTP streaming service...")
    # Note: In production, use process manager (systemd, supervisor, etc.) to stop the process
    # This task is mainly for documentation
    puts "To stop the streaming service, send SIGTERM or SIGINT to the process"
  end
end
