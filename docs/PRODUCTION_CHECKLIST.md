# Production Go-Live Checklist

## Pre-Deployment

### Code Quality
- [ ] All tests passing (`rails test`)
- [ ] No RuboCop violations (`bundle exec rubocop`)
- [ ] No Brakeman security issues (`bundle exec brakeman`)
- [ ] No Bundler audit issues (`bundle exec bundler-audit check`)
- [ ] Code coverage > 80%

### Configuration
- [ ] All environment variables set in production
- [ ] `config/algo.yml` configured for production
- [ ] `config/recurring.yml` schedules verified
- [ ] Database credentials configured
- [ ] API rate limits understood and configured

### Database
- [ ] All migrations applied
- [ ] Database indexes verified (`rails hardening:indexes`)
- [ ] Backup strategy in place
- [ ] Database connection pool configured

### Security
- [ ] No secrets in code (`rails hardening:secrets`)
- [ ] API keys stored securely (environment variables)
- [ ] TLS/SSL configured for all external APIs
- [ ] SQL injection prevention verified (ActiveRecord)
- [ ] Input validation on all services

## Testing

### Backtesting
- [ ] Run comprehensive backtest (3+ months)
- [ ] Validate backtest results
- [ ] Compare across different market conditions
- [ ] Verify no look-ahead bias

### Integration Testing
- [ ] Test instrument import
- [ ] Test candle ingestion
- [ ] Test screener pipeline
- [ ] Test signal generation
- [ ] Test Telegram notifications
- [ ] Test job scheduling

### Load Testing
- [ ] Test daily ingestion with full instrument list
- [ ] Test screener with 1000+ instruments
- [ ] Verify API rate limits not exceeded
- [ ] Check job queue performance

## Monitoring Setup

### Metrics
- [ ] Metrics tracking enabled
- [ ] Daily metrics dashboard accessible
- [ ] Alert thresholds configured

### Logging
- [ ] Structured logging configured
- [ ] Log retention policy set
- [ ] Error logging verified

### Alerts
- [ ] Telegram alerts tested
- [ ] Job failure alerts working
- [ ] API error alerts working
- [ ] Health check alerts working

## Operational Readiness

### Documentation
- [ ] README.md complete
- [ ] Runbook reviewed and tested
- [ ] Architecture documented
- [ ] Environment variables documented

### Team Training
- [ ] Team trained on operations
- [ ] Runbook procedures tested
- [ ] Emergency procedures understood
- [ ] Rollback plan documented

### Backup & Recovery
- [ ] Database backup automated
- [ ] Configuration backup automated
- [ ] Recovery procedure tested
- [ ] Backup retention policy set

## Go-Live Steps

1. **Enable Dry-Run Mode**
   ```bash
   export DRY_RUN=true
   ```

2. **Deploy to Production**
   - Run migrations
   - Restart application
   - Start SolidQueue workers

3. **Verify Deployment**
   ```bash
   rails hardening:check
   rails monitor:health
   ```

4. **Monitor First Day**
   - Watch job execution
   - Monitor API usage
   - Check error logs
   - Verify notifications

5. **Gradual Rollout**
   - Start with dry-run mode
   - Monitor for 1 week
   - Enable manual approval for first 30 trades
   - Full automation after validation

## Post-Go-Live

### Week 1
- [ ] Daily review of metrics
- [ ] Verify all jobs running correctly
- [ ] Check for any errors
- [ ] Review generated signals

### Month 1
- [ ] Compare live performance vs backtest
- [ ] Review and optimize parameters
- [ ] Analyze signal quality
- [ ] Adjust risk parameters if needed

## Emergency Procedures

### Stop All Execution
1. Set `DRY_RUN=true`
2. Stop SolidQueue workers
3. Comment out jobs in `config/recurring.yml`

### Rollback
1. Revert code deployment
2. Restore database from backup if needed
3. Restart services

### Contact
- System Administrator: [Contact Info]
- On-Call Engineer: [Contact Info]


