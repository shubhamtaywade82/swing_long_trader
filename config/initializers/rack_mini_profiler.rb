# frozen_string_literal: true

# Rack Mini Profiler configuration for request and query profiling
# Enable/disable via ENABLE_MINI_PROFILER environment variable (default: true in development)
if defined?(Rack::MiniProfiler)
  enable_profiler = ENV.fetch("ENABLE_MINI_PROFILER", Rails.env.development?.to_s).to_s.downcase == "true"

  if enable_profiler
    Rack::MiniProfiler.config.position = "bottom-right"
    Rack::MiniProfiler.config.start_hidden = false
    Rack::MiniProfiler.config.skip_paths = [
      "/assets",
      "/favicon.ico",
      "/robots.txt"
    ]

    # Show SQL queries
    Rack::MiniProfiler.config.enable_advanced_debugging_tools = true

    # Customize storage (default: memory)
    # Rack::MiniProfiler.config.storage = Rack::MiniProfiler::MemoryStore

    # Show backtrace for slow queries
    Rack::MiniProfiler.config.backtrace_remove = Rails.root.to_s
    Rack::MiniProfiler.config.backtrace_includes = [/^\/?(app|config|lib|test)/]

    Rails.logger.info "📊 Rack Mini Profiler enabled - Request profiling active"
  else
    # Disable the profiler
    Rack::MiniProfiler.config.enabled = false
    Rails.logger.info "⏸️  Rack Mini Profiler disabled"
  end
end
