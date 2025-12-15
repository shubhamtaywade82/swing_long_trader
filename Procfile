web: bundle exec rails server -p ${PORT:-3000} -b 0.0.0.0
worker: QUEUES=screener_now,screener,ai_evaluation,execution,monitoring,data_ingestion,background,notifier bundle exec rails solid_queue:start
market_stream: bundle exec rake market:start_stream
