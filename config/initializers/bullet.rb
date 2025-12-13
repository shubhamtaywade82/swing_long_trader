# frozen_string_literal: true

# Bullet gem configuration for detecting N+1 queries and unused eager loading
# Enable/disable via ENABLE_BULLET environment variable (default: true in development)
if defined?(Bullet)
  enable_bullet = ENV.fetch("ENABLE_BULLET", Rails.env.development?.to_s).to_s.downcase == "true"

  if enable_bullet
    Bullet.enable = true
    Bullet.alert = true
    Bullet.bullet_logger = true
    Bullet.console = true
    Bullet.rails_logger = true
    Bullet.add_footer = true

    # Detect N+1 queries
    Bullet.n_plus_one_query_enable = true

    # Detect unused eager loading
    Bullet.unused_eager_loading_enable = true

    # Detect counter cache queries
    Bullet.counter_cache_enable = true

    # Skip specific paths if needed
    # Bullet.skip_html_injection = true

    Rails.logger.info "🔍 Bullet enabled - N+1 query detection active"
  else
    Bullet.enable = false
    Rails.logger.info "⏸️  Bullet disabled"
  end
end
