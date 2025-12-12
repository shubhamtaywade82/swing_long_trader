# Kamal Deployment Guide

**Complete guide to deploying the Swing + Long-Term Trading System using Kamal**

---

## Overview

This project uses [Kamal](https://kamal-deploy.org/) for zero-downtime deployments. Kamal builds Docker images, pushes them to a registry, and deploys them to your servers.

---

## Prerequisites

### 1. Install Kamal

```bash
# Kamal is included in Gemfile, install dependencies
bundle install

# Verify Kamal is available
bundle exec kamal version
```

### 2. Configure Server Access

Ensure you can SSH into your deployment server:

```bash
# Test SSH access
ssh user@your-server-ip

# If using SSH keys, ensure they're set up
ssh-copy-id user@your-server-ip  # If needed
```

### 3. Configure Docker Registry

You need a Docker registry to store images. Options:

- **Docker Hub**: `hub.docker.com`
- **GitHub Container Registry**: `ghcr.io`
- **DigitalOcean Container Registry**: `registry.digitalocean.com`
- **Self-hosted**: Your own registry server

**Update `config/deploy.yml`:**

```yaml
registry:
  server: hub.docker.com  # or your registry
  username: your-username
  password:
    - KAMAL_REGISTRY_PASSWORD
```

### 4. Configure Secrets

Edit `.kamal/secrets` to set up your secrets:

```bash
# Example: Using Rails credentials
RAILS_MASTER_KEY=$(cat config/master.key)

# Example: Using environment variables
KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD

# Example: Using 1Password (if configured)
# SECRETS=$(kamal secrets fetch --adapter 1password ...)
# RAILS_MASTER_KEY=$(kamal secrets extract RAILS_MASTER_KEY ${SECRETS})
```

**Important:** Never commit actual secrets to git. Use environment variables or a password manager.

### 5. Update Server Configuration

Edit `config/deploy.yml` and update:

```yaml
servers:
  web:
    - your-server-ip-or-hostname  # Replace 192.168.0.1
```

### 6. Configure Environment Variables

Set production environment variables in `config/deploy.yml`:

```yaml
env:
  secret:
    - RAILS_MASTER_KEY
  clear:
    SOLID_QUEUE_IN_PUMA: true
    RAILS_ENV: production
    # Add your other environment variables here
    # DHANHQ_CLIENT_ID: your_client_id
    # DHANHQ_ACCESS_TOKEN: your_access_token
    # TELEGRAM_BOT_TOKEN: your_bot_token
    # TELEGRAM_CHAT_ID: your_chat_id
```

**Note:** For sensitive values, add them to `.kamal/secrets` and reference them in `env.secret`.

---

## Deployment Commands

### First-Time Setup

#### 1. Setup Server

```bash
# Install Docker and required dependencies on server
bundle exec kamal setup
```

This will:
- Install Docker on the server
- Create necessary directories
- Set up Traefik (reverse proxy)
- Configure networking

#### 2. Build and Push Image

```bash
# Build Docker image and push to registry
bundle exec kamal build push
```

Or do both in one command:

```bash
bundle exec kamal deploy
```

### Regular Deployment

#### Deploy Application

```bash
# Full deployment (build, push, deploy)
bundle exec kamal deploy

# Deploy without building (if image already exists)
bundle exec kamal deploy --skip-build

# Deploy to specific destination (if configured)
bundle exec kamal deploy -d production
```

#### Deploy with Migrations

```bash
# Deploy and run migrations
bundle exec kamal app exec "bin/rails db:migrate"
bundle exec kamal deploy
```

Or use the pre-deploy hook (see Hooks section below).

---

## Useful Commands

### Application Management

```bash
# View application logs
bundle exec kamal logs
bundle exec kamal logs -f  # Follow logs

# Access Rails console
bundle exec kamal console

# Access shell
bundle exec kamal shell

# Access database console
bundle exec kamal dbc

# Check application details
bundle exec kamal app details

# List running containers
bundle exec kamal app containers

# Check application version
bundle exec kamal app version
```

### Server Management

```bash
# Check server configuration
bundle exec kamal server exec "docker ps"

# Check server resources
bundle exec kamal server exec "df -h"
bundle exec kamal server exec "free -h"

# Access server shell
bundle exec kamal server exec "bash"
```

### Image Management

```bash
# Build image only
bundle exec kamal build

# Push image only
bundle exec kamal push

# Remove old images
bundle exec kamal app prune

# List images
bundle exec kamal app images
```

### Rollback

```bash
# Rollback to previous version
bundle exec kamal rollback

# Rollback to specific version
bundle exec kamal rollback -v <version>
```

### Health Checks

```bash
# Check if app is healthy
bundle exec kamal app exec "bin/rails runner 'puts \"OK\"'"

# Run hardening checks
bundle exec kamal app exec "bin/rails hardening:check"

# Check metrics
bundle exec kamal app exec "bin/rails metrics:daily"
```

---

## Deployment Hooks

Kamal supports hooks that run at different stages. Sample hooks are in `.kamal/hooks/`.

### Available Hooks

- **pre-build**: Runs before building Docker image
- **pre-deploy**: Runs before deployment
- **post-deploy**: Runs after deployment
- **pre-app-boot**: Runs before starting application
- **post-app-boot**: Runs after starting application

### Enable Hooks

Copy sample hooks and customize:

```bash
# Copy and enable pre-deploy hook
cp .kamal/hooks/pre-deploy.sample .kamal/hooks/pre-deploy
chmod +x .kamal/hooks/pre-deploy

# Copy and enable post-deploy hook
cp .kamal/hooks/post-deploy.sample .kamal/hooks/post-deploy
chmod +x .kamal/hooks/post-deploy
```

### Example: Pre-Deploy Hook with Migrations

Create `.kamal/hooks/pre-deploy`:

```bash
#!/bin/bash
set -e

echo "Running database migrations..."
bundle exec kamal app exec "bin/rails db:migrate"

echo "Pre-deploy checks complete"
```

### Example: Post-Deploy Hook with Health Check

Create `.kamal/hooks/post-deploy`:

```bash
#!/bin/bash
set -e

echo "Running health checks..."
bundle exec kamal app exec "bin/rails hardening:check"

echo "Checking SolidQueue status..."
bundle exec kamal app exec "bin/rails solid_queue:status"

echo "Deployment complete: $KAMAL_VERSION"
```

---

## Complete Deployment Workflow

### Initial Setup (One-Time)

```bash
# 1. Configure config/deploy.yml
#    - Update server IPs
#    - Configure registry
#    - Set environment variables

# 2. Configure .kamal/secrets
#    - Set RAILS_MASTER_KEY
#    - Set registry password (if needed)

# 3. Setup server
bundle exec kamal setup

# 4. Build and deploy
bundle exec kamal deploy
```

### Regular Deployment

```bash
# 1. Ensure code is committed and pushed
git add .
git commit -m "Your changes"
git push

# 2. Deploy
bundle exec kamal deploy

# 3. Verify deployment
bundle exec kamal logs -f
bundle exec kamal app exec "bin/rails hardening:check"
```

### Deployment with Migrations

```bash
# Option 1: Run migrations before deploy (recommended)
bundle exec kamal app exec "bin/rails db:migrate"
bundle exec kamal deploy

# Option 2: Use pre-deploy hook (automatic)
# Enable .kamal/hooks/pre-deploy (see above)
bundle exec kamal deploy
```

---

## Configuration Examples

### Using Docker Hub

```yaml
# config/deploy.yml
registry:
  server: hub.docker.com
  username: your-username
  password:
    - KAMAL_REGISTRY_PASSWORD
```

```bash
# .kamal/secrets
KAMAL_REGISTRY_PASSWORD=$DOCKER_HUB_TOKEN
```

### Using GitHub Container Registry

```yaml
# config/deploy.yml
registry:
  server: ghcr.io
  username: your-github-username
  password:
    - KAMAL_REGISTRY_PASSWORD
```

```bash
# .kamal/secrets
KAMAL_REGISTRY_PASSWORD=$(gh auth token)
```

### Using PostgreSQL Accessory

```yaml
# config/deploy.yml
accessories:
  db:
    image: postgres:15
    host: 192.168.0.2
    port: "127.0.0.1:5432:5432"
    env:
      clear:
        POSTGRES_DB: swing_long_trader_production
      secret:
        - POSTGRES_PASSWORD
    directories:
      - data:/var/lib/postgresql/data
```

```bash
# .kamal/secrets
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
```

### Using Redis Accessory

```yaml
# config/deploy.yml
accessories:
  redis:
    image: valkey/valkey:8
    host: 192.168.0.2
    port: 6379
    directories:
      - data:/data
```

---

## Troubleshooting

### Build Fails

```bash
# Check build logs
bundle exec kamal build --verbose

# Test Docker build locally
docker build -t test-image .

# Check Dockerfile
cat Dockerfile
```

### Push Fails

```bash
# Verify registry credentials
echo $KAMAL_REGISTRY_PASSWORD

# Test registry login
docker login your-registry.com

# Check registry configuration
cat config/deploy.yml | grep -A 5 registry
```

### Deployment Fails

```bash
# Check server logs
bundle exec kamal server exec "docker logs swing_long_trader-web"

# Check application logs
bundle exec kamal logs

# Check server resources
bundle exec kamal server exec "df -h"
bundle exec kamal server exec "free -h"

# Verify server access
bundle exec kamal server exec "whoami"
```

### Application Won't Start

```bash
# Check container status
bundle exec kamal app containers

# Check application logs
bundle exec kamal logs -f

# Access container shell
bundle exec kamal shell

# Check environment variables
bundle exec kamal app exec "env | grep RAILS"
```

### Database Connection Issues

```bash
# Check database is accessible
bundle exec kamal app exec "bin/rails db:version"

# Test database connection
bundle exec kamal console
# In console: ActiveRecord::Base.connection.execute("SELECT 1")

# Check database configuration
bundle exec kamal app exec "bin/rails runner 'puts ActiveRecord::Base.configurations'"
```

### SolidQueue Not Running

```bash
# Check SolidQueue status
bundle exec kamal app exec "bin/rails solid_queue:status"

# Check SolidQueue configuration
bundle exec kamal app exec "env | grep SOLID_QUEUE"

# Restart application
bundle exec kamal app restart
```

---

## Best Practices

### 1. Always Test Locally First

```bash
# Run tests
rails test

# Run hardening checks
rails hardening:check

# Test Docker build locally
docker build -t swing_long_trader:test .
```

### 2. Use Pre-Deploy Hooks

Enable hooks for:
- Database migrations
- Health checks
- Backup creation

### 3. Monitor After Deployment

```bash
# Watch logs for first few minutes
bundle exec kamal logs -f

# Check metrics
bundle exec kamal app exec "bin/rails metrics:daily"

# Verify jobs are running
bundle exec kamal app exec "bin/rails solid_queue:status"
```

### 4. Keep Secrets Secure

- Never commit secrets to git
- Use environment variables or password managers
- Rotate secrets regularly
- Use different secrets for different environments

### 5. Use Rollback Strategy

Always know how to rollback:

```bash
# Keep previous version available
bundle exec kamal rollback

# Or redeploy previous commit
git checkout <previous-commit>
bundle exec kamal deploy
```

### 6. Backup Before Major Changes

```bash
# Backup database before migrations
bundle exec kamal app exec "pg_dump swing_long_trader_production > backup.sql"

# Or use Rails backup task if available
bundle exec kamal app exec "bin/rails db:backup"
```

---

## Quick Reference

### Common Commands

```bash
# Setup (first time)
bundle exec kamal setup

# Deploy
bundle exec kamal deploy

# View logs
bundle exec kamal logs -f

# Rails console
bundle exec kamal console

# Run migrations
bundle exec kamal app exec "bin/rails db:migrate"

# Rollback
bundle exec kamal rollback

# Health check
bundle exec kamal app exec "bin/rails hardening:check"
```

### Configuration Files

- `config/deploy.yml` - Main deployment configuration
- `.kamal/secrets` - Secrets management
- `.kamal/hooks/` - Deployment hooks
- `Dockerfile` - Docker image definition

---

## Next Steps

1. **Configure Your Environment**: Update `config/deploy.yml` with your server details
2. **Set Up Secrets**: Configure `.kamal/secrets` with your credentials
3. **Test Deployment**: Run `bundle exec kamal setup` and `bundle exec kamal deploy`
4. **Enable Hooks**: Copy and customize hooks in `.kamal/hooks/`
5. **Monitor**: Set up monitoring and alerts for production

---

## Additional Resources

- [Kamal Documentation](https://kamal-deploy.org/)
- [Docker Documentation](https://docs.docker.com/)
- [Deployment Quickstart](DEPLOYMENT_QUICKSTART.md) - Step-by-step deployment guide
- [Production Checklist](PRODUCTION_CHECKLIST.md) - Pre-deployment checklist
- [Runbook](runbook.md) - Operational procedures

---

**Last Updated:** After Kamal deployment setup
