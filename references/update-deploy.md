# Update Deployment Guide

## Overview

### First Deployment vs Update Deployment

| Dimension | First Deployment | Update Deployment |
|-----------|-----------------|-------------------|
| Definition | Setting up a complete runtime environment from scratch | Rebuilding and restarting services after code changes |
| Environment Detection | Requires detecting OS, language version, package manager | Skipped; environment is already ready |
| Dependency Installation | Full installation | Only install new/changed dependencies |
| Configuration Generation | Generate `.env`, `nginx.conf`, `docker-compose.yml`, etc. | Only check for new configuration items |
| Database | Initialize database and tables | Run incremental migrations (if any) |
| Risk | Low (new environment, no legacy baggage) | High (must ensure no disruption to live services) |

**Core Principle**: The goal of update deployment is to safely release code changes to production without interrupting existing services. When performing an update deployment, the AI **must strictly follow the four phases below in order** and must not skip any step.

---

## Complete Update Deployment Workflow (AI Must Follow This Order Strictly)

### Phase 1: Pre-Deploy Check

> **AI Note**: All checks in this phase must pass before proceeding to Phase 2. If any check fails, the issue must be resolved before continuing.

#### 1.1 Back Up the Current Version

**Why**: In case the update fails, you can immediately roll back to the last working version, minimizing downtime.

**Docker Deployment Backup:**

```bash
# Record currently running image information
docker compose ps --format "table {{.Name}}\t{{.Image}}\t{{.Status}}" > /backups/pre-deploy-$(date +%Y%m%d%H%M%S).txt

# Save the current application image (only save the app service image, not the database image)
docker save $(docker compose images -q app) -o /backups/app-image-$(date +%Y%m%d%H%M%S).tar
```

**Server Deployment Backup:**

```bash
# Package the current code (exclude unnecessary directories to save space and time)
cd /var/www/myapp
tar -czf /backups/myapp-backup-$(date +%Y%m%d%H%M%S).tar.gz \
  --exclude='node_modules' \
  --exclude='.git' \
  --exclude='venv' \
  --exclude='__pycache__' \
  --exclude='.next' \
  --exclude='dist' \
  --exclude='*.log' \
  .
```

**Database Backup (only execute when this update involves database schema changes):**

```bash
# MySQL
mysqldump -u root -p"$DB_PASSWORD" "$DB_NAME" > /backups/db-backup-$(date +%Y%m%d%H%M%S).sql

# PostgreSQL
pg_dump -U "$DB_USER" -d "$DB_NAME" -F c -f /backups/db-backup-$(date +%Y%m%d%H%M%S).dump

# MongoDB
mongodump --uri="$MONGO_URI" --out=/backups/mongo-backup-$(date +%Y%m%d%H%M%S)
```

**Automatic Cleanup of Old Backups (keep the most recent 3):**

```bash
# Clean up code backups
ls -t /backups/myapp-backup-*.tar.gz | tail -n +4 | xargs -r rm -f

# Clean up image backups
ls -t /backups/app-image-*.tar | tail -n +4 | xargs -r rm -f

# Clean up database backups
ls -t /backups/db-backup-* | tail -n +4 | xargs -r rm -f
```

#### 1.2 Review Changes

**Purpose**: Confirm which files have changed and determine whether the changes involve high-risk operations such as database migrations or configuration changes.

```bash
# View an overview of the latest commit's changes
git log --oneline -5
git diff --stat HEAD~1

# If there are multiple commits, view all undeployed changes
git diff --stat origin/main...HEAD  # If on a local branch
git diff --stat HEAD~3..HEAD        # View the last 3 commits

# Check if database migration files are included
git diff --name-only HEAD~1 | grep -E '(migration|migrate|schema)' && echo "WARNING: Database migration files have changed!" || echo "No database migration changes"

# Check if configuration file changes are included
git diff --name-only HEAD~1 | grep -E '(\.env\.example|docker-compose|nginx\.conf|Dockerfile)' && echo "WARNING: Configuration files have changed!" || echo "No configuration file changes"
```

**Change Classification and Handling Strategy:**

| Change Type | Risk Level | Additional Actions |
|-------------|-----------|-------------------|
| Frontend-only code (HTML/CSS/JS/images) | Low | Normal workflow |
| Backend business logic | Medium | Focus on checking related APIs after deployment |
| Database migration files | High | Must back up database; run migrations after deployment |
| Environment variables / configuration files | High | Must compare with `.env.example` and confirm new variables |
| Dependency version changes (package.json / requirements.txt) | Medium | Dependencies must be reinstalled |
| Dockerfile changes | Medium | Images must be rebuilt |

#### 1.3 Pre-Check the Environment

**Purpose**: Confirm the deployment environment is still healthy to avoid stacking an update on an already abnormal environment, which would make troubleshooting difficult.

```bash
# Check disk space (at least 2GB free required)
AVAILABLE=$(df / | awk 'NR==2 {print $4}')
if [ "$AVAILABLE" -lt 2097152 ]; then
  echo "ERROR: Insufficient disk space, available: $((AVAILABLE/1024))MB, need at least 2048MB"
  exit 1
fi
echo "Sufficient disk space: $((AVAILABLE/1024/1024))GB available"

# Docker deployment: check if Docker daemon is running
docker info > /dev/null 2>&1 && echo "Docker is running normally" || echo "ERROR: Docker daemon is not running"

# Check if the service is currently healthy
curl -sf http://localhost:${PORT}/health && echo "Service health check passed" || echo "WARNING: Service health check failed, the current service may already be abnormal"
```

---

### Phase 2: Execute the Update

> **AI Note**: Choose one of the three paths below based on the actual deployment method. Do not mix commands from different paths.

#### 2.1 Docker Deployment Path

```bash
# Step 1: Pull the latest code
git fetch origin
git pull origin main

# Step 2: Check if the .env file has new variables
diff <(grep -v '^#' .env | grep -v '^$' | sort) \
     <(grep -v '^#' .env.example | grep -v '^$' | sort) \
  && echo ".env has no new variables" \
  || echo "WARNING: .env differs from .env.example, please check if new variables need to be added"

# Step 3: Rebuild images (only rebuild the application image, not database and other base services)
docker compose build --no-cache app

# Step 4: Rolling update (only update the app service; database and cache are unaffected)
docker compose up -d --build app

# Step 5: Wait for health check to pass (wait up to 120 seconds)
echo "Waiting for service to start..."
for i in $(seq 1 24); do
  STATUS=$(docker compose ps --format "{{.Health}}" app 2>/dev/null || echo "unknown")
  if [ "$STATUS" = "healthy" ]; then
    echo "Service started healthily"
    break
  fi
  if [ "$i" -eq 24 ]; then
    echo "ERROR: Service startup timed out (120 seconds), please check logs"
    docker compose logs --tail=50 app
    exit 1
  fi
  sleep 5
done

# Step 6: If there are database migrations, execute them after the service is healthy
if git diff --name-only HEAD~1 | grep -qE '(migration|migrate)'; then
  echo "Database migration files detected, running migrations..."
  docker compose exec -T app npx prisma migrate deploy
  # Or: docker compose exec -T app python manage.py migrate --noinput
  # Or: docker compose exec -T app npx typeorm migration:run
  echo "Database migration complete"
fi

# Step 7: Clean up old images
docker image prune -f
```

#### 2.2 Server Deployment Path (Nginx + systemd)

```bash
# Step 1: Pull the latest code
git fetch origin
git pull origin main

# Step 2: Install new dependencies (production dependencies only)
# Node.js project
npm ci --production
# Python project
# pip install -r requirements.txt --no-cache-dir

# Step 3: Execute the build
npm run build
# Build output is typically in the dist/ or build/ directory

# Step 4: If there are database migrations
if git diff --name-only HEAD~1 | grep -qE '(migration|migrate)'; then
  echo "Database migration files detected, running migrations..."
  python manage.py migrate --noinput
  # Or: npx prisma migrate deploy
  echo "Database migration complete"
fi

# Step 5: Restart the service
sudo systemctl restart myapp

# Step 6: Wait for the service to be ready and check status
sleep 3
sudo systemctl status myapp --no-pager
if [ $? -ne 0 ]; then
  echo "ERROR: Service failed to start, checking error logs..."
  sudo journalctl -u myapp --since "1 min ago" --no-pager
  exit 1
fi

# Step 7: Nginx does not need to restart (reverse proxy config unchanged, only backend service restarted)
# Only needed if this update involves Nginx configuration changes:
# sudo nginx -t && sudo systemctl reload nginx
```

#### 2.3 Remote Server Deployment (SSH)

```bash
# Step 1: Sync files from local to remote server
# Exclude directories and files that don't need to be uploaded
rsync -avz --delete \
  --exclude='node_modules' \
  --exclude='.git' \
  --exclude='.env' \
  --exclude='venv' \
  --exclude='__pycache__' \
  --exclude='.next' \
  --exclude='dist' \
  --exclude='*.log' \
  ./ user@server:/var/www/myapp/

# Step 2: SSH remote execution of update commands (combined into one command to ensure atomicity)
ssh user@server bash -c "'cd /var/www/myapp && \
  npm ci --production && \
  npm run build && \
  sudo systemctl restart myapp && \
  sleep 3 && \
  sudo systemctl status myapp --no-pager'"

# Step 3: Remote health check
ssh user@server "curl -sf http://localhost:${PORT}/health" \
  && echo "Remote service health check passed" \
  || echo "ERROR: Remote service health check failed"
```

---

### Phase 3: Post-Deploy Verification

> **AI Note**: All verification items in this phase must pass for the deployment to be considered successful. If any item fails, you must immediately investigate or perform a rollback.

#### 3.1 Health Check

```bash
# Basic health check
curl -sf -o /dev/null -w "HTTP Status: %{http_code}\n" https://your-domain.com/health
# Expected output: HTTP Status: 200

# Health check with timeout (wait up to 30 seconds)
timeout 30 bash -c 'until curl -sf https://your-domain.com/health > /dev/null 2>&1; do sleep 2; done' \
  && echo "Health check passed" \
  || echo "ERROR: Health check timed out"
```

#### 3.2 Check Application Logs

```bash
# Docker deployment
docker compose logs --tail=50 app
docker compose logs --tail=50 app 2>&1 | grep -iE '(error|exception|fatal|panic)' && echo "WARNING: Error logs found" || echo "No error logs"

# systemd service
sudo journalctl -u myapp --since "2 min ago" --no-pager
sudo journalctl -u myapp --since "2 min ago" --no-pager | grep -iE '(error|exception|fatal|panic)' && echo "WARNING: Error logs found" || echo "No error logs"

# Nginx error log
sudo tail -20 /var/log/nginx/error.log
```

#### 3.3 Functional Verification

Depending on the project type, verify the following key functionality:

- **Homepage loading**: `curl -sf -o /dev/null -w "%{http_code}" https://your-domain.com/` should return 200
- **API endpoints**: Test that core API endpoints respond normally
- **Static assets**: Confirm that CSS/JS/images and other static assets load correctly
- **Database read/write**: If database changes are involved, verify that CRUD operations work normally

---

### Phase 4: Cleanup

```bash
# Docker cleanup
docker image prune -f          # Remove dangling images (images not referenced by any container)
docker builder prune -f         # Clean build cache

# Server cleanup
# Remove old backup files (keep the most recent 3)
ls -t /backups/myapp-backup-*.tar.gz | tail -n +4 | xargs -r rm -f
ls -t /backups/app-image-*.tar | tail -n +4 | xargs -r rm -f
ls -t /backups/db-backup-* | tail -n +4 | xargs -r rm -f

# Clean up build temporary files
rm -rf /tmp/build-* /tmp/npm-* /tmp/pip-*

# Log cleanup (limit log size to 100MB)
sudo journalctl --vacuum-size=100M

# Final disk check
df -h /
echo "Post-deployment disk space confirmed"
```

---

## Rollback Mechanism

> **AI Note**: When Phase 3 verification fails, **you must immediately execute a rollback**. Do not attempt to fix issues while in a failed state. Fixes should be performed in the development environment after rolling back and restoring service.

### Trigger Conditions

Immediately trigger a rollback if any of the following conditions are met:

1. Health check fails 3 consecutive times
2. Persistent errors appear in logs after service startup (not intermittent errors)
3. Key functionality is unavailable (homepage inaccessible, core API returning 500)
4. Response time is abnormally high (more than 3x the normal value)

### Docker Rollback

```bash
# Step 1: Tag the current (broken) version
docker tag myapp:latest myapp:failed-$(date +%Y%m%d%H%M%S)

# Step 2: Stop the current container
docker compose down app

# Step 3: Restore the backup image
docker load -i /backups/app-image-YYYYMMDDHHMMSS.tar

# Step 4: Restart using the backup image
docker compose up -d app

# Step 5: Verify the rollback succeeded
sleep 5
docker compose ps
curl -sf http://localhost:${PORT}/health && echo "Rollback successful" || echo "Rollback failed, manual intervention required"
```

### Server Rollback

```bash
# Step 1: Stop the current service
sudo systemctl stop myapp

# Step 2: Restore the code backup (find the most recent backup file)
BACKUP_FILE=$(ls -t /backups/myapp-backup-*.tar.gz | head -1)
echo "Using backup file: $BACKUP_FILE"

# Step 3: Clean current code and restore
cd /var/www/myapp
rm -rf $(ls -A | grep -v '^\.env$')  # Preserve the .env file
tar -xzf "$BACKUP_FILE"

# Step 4: Reinstall dependencies and build
npm ci --production
npm run build

# Step 5: Start the service
sudo systemctl start myapp
sleep 3
sudo systemctl status myapp --no-pager

# Step 6: Verify the rollback
curl -sf http://localhost:${PORT}/health && echo "Rollback successful" || echo "Rollback failed, manual intervention required"
```

### Database Rollback

```bash
# Django rollback to a specific migration
python manage.py migrate app_name migration_name

# Prisma rollback
npx prisma migrate resolve --rolled-back migration_name

# If a database backup exists, restore directly (most thorough but changes during the rollback period will be lost)
# MySQL
mysql -u root -p"$DB_PASSWORD" "$DB_NAME" < /backups/db-backup-YYYYMMDDHHMMSS.sql

# PostgreSQL
pg_restore -U "$DB_USER" -d "$DB_NAME" -c /backups/db-backup-YYYYMMDDHHMMSS.dump

# MongoDB
mongorestore --uri="$MONGO_URI" --drop /backups/mongo-backup-YYYYMMDDHHMMSS
```

---

## Zero-Downtime Deployment Strategies

### Docker Rolling Update

The default behavior of `docker compose up -d --build` is a rolling update: it starts the new container first, and only stops the old container after the new container passes its health check. Zero downtime is achieved without additional configuration.

For multi-instance rolling updates:

```yaml
# docker-compose.yml
services:
  app:
    image: myapp:latest
    deploy:
      replicas: 2
      update_config:
        parallelism: 1      # Update 1 instance at a time
        delay: 10s          # 10-second interval between instances
        order: start-first  # Start new before stopping old
      restart_policy:
        condition: on-failure
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:3000/health"]
      interval: 5s
      timeout: 3s
      retries: 3
```

### Blue-Green Deployment (Advanced)

Suitable for scenarios with extremely high availability requirements:

```
                    ┌──────────────┐
                    │   Nginx /    │
    User Request ──►│   Load       │──────┐
                    │   Balancer   │      │
                    └──────────────┘      │
                               ┌─────────┴─────────┐
                               ▼                   ▼
                        ┌─────────────┐     ┌─────────────┐
                        │  Blue Env   │     │  Green Env  │
                        │  (Current)  │     │  (New)      │
                        │  v1.2.0     │     │  v1.3.0     │
                        └─────────────┘     └─────────────┘
```

**Operation Flow:**

1. All current traffic points to the blue environment (production)
2. Deploy the new version code in the green environment
3. Execute database migrations in the green environment (if needed)
4. Verify the green environment passes health checks
5. Modify the Nginx upstream or DNS to switch traffic to the green environment
6. Monitor the green environment's operation (for at least 5 minutes)
7. If issues arise, immediately switch back to the blue environment (only need to revert the upstream config and reload Nginx)

```bash
# Nginx switch example
# Switch to green environment
sudo sed -i 's/upstream blue/upstream green/' /etc/nginx/conf.d/upstream.conf
sudo nginx -t && sudo systemctl reload nginx

# Switch back to blue environment
sudo sed -i 's/upstream green/upstream blue/' /etc/nginx/conf.d/upstream.conf
sudo nginx -t && sudo systemctl reload nginx
```

### PM2 Zero Downtime

```bash
# Graceful reload: wait for existing requests to finish before restarting
pm2 reload app

# Difference from pm2 restart:
# pm2 restart  → Kills the process directly; in-flight requests are lost
# pm2 reload   → Forks a new process first, then terminates the old process only after the new one is ready

# Confirm reload succeeded
pm2 status
pm2 logs app --lines 20 --nostream
```

---

## CI/CD Automatic Triggering

### GitHub Actions Example

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to server
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.HOST }}
          username: ${{ secrets.USERNAME }}
          key: ${{ secrets.SSH_KEY }}
          script: |
            cd /var/www/myapp
            git pull origin main
            npm ci --production
            npm run build
            sudo systemctl restart myapp
            sleep 3
            curl -sf http://localhost:3000/health || exit 1
```

### Webhook Trigger

Deploy a listener script on the server; push events from the code repository trigger automatic deployment:

```bash
# /opt/deploy/webhook-listener.sh
#!/bin/bash
while true; do
  # Listen on the webhook port (requires a webhook service such as webhookd)
  # Execute the deployment script upon receiving a push event
  /opt/deploy/deploy.sh >> /var/log/deploy.log 2>&1
done
```

### Scheduled Deployment (Not Recommended)

```bash
# Cron-based pull (only as a last resort; CI/CD is strongly recommended)
# */30 * * * * cd /var/www/myapp && git pull origin main && npm run build && sudo systemctl restart myapp
```

> **Warning**: Scheduled deployment cannot guarantee code quality (untested code will also be deployed) and provides no deployment history traceability. Use only in extreme cases where CI/CD cannot be set up.

---

## AI Operation Checklist

Each time an update deployment is executed, the AI must confirm the following checklist item by item:

- [ ] Phase 1.1 - Current version has been backed up (code + images + database if needed)
- [ ] Phase 1.2 - Changes have been reviewed (confirmed whether there are migration/configuration changes)
- [ ] Phase 1.3 - Environment has been pre-checked (disk space, Docker, service health)
- [ ] Phase 2 - The correct deployment path has been selected and executed step by step
- [ ] Phase 3.1 - Health check passed
- [ ] Phase 3.2 - No abnormal errors in application logs
- [ ] Phase 3.3 - Key functionality verification passed
- [ ] Phase 4 - Old backups and temporary files have been cleaned up
- [ ] If verification failed - Rollback has been executed and service has been restored
