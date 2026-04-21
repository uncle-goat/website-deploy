# Backend API Service Deployment Guide

## Express.js Deployment

### PM2 Process Management

PM2 is the preferred process management tool for Node.js production environments, providing process daemonization, automatic restarts, cluster mode, and log management.

**Why choose PM2:**
- Process daemonization: automatically restarts processes after a crash
- Cluster mode: fully utilizes multi-core CPUs
- Log management: centrally manages application logs
- Load monitoring: real-time CPU and memory usage monitoring

**Installation:**
```bash
npm install -g pm2
```

**Starting the application:**
```bash
# Basic start
pm2 start src/index.js --name api --env production

# Cluster mode (uses all CPU cores)
pm2 start src/index.js -i max --name api

# Specify the number of instances
pm2 start src/index.js -i 4 --name api
```

**Common commands:**
```bash
pm2 list          # View all processes
pm2 logs api      # View logs
pm2 restart api   # Restart the application
pm2 stop api      # Stop the application
pm2 delete api    # Remove the application
pm2 monit         # Real-time monitoring dashboard
pm2 info api      # View detailed information
```

**Startup on boot:**
```bash
pm2 startup       # Generate the startup script
pm2 save          # Save the current process list
```

### systemd Deployment (Alternative to PM2)

If you prefer not to use PM2, you can manage the service directly with systemd.

**Using the generation script:**
```bash
bash generate-systemd-service.sh --name my-api --user deploy --workdir /opt/app --command "/usr/bin/node /path/to/app/src/index.js"
```

**Manually creating the service file:**
```ini
# /etc/systemd/system/my-api.service
[Unit]
Description=My API Service
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/opt/app
ExecStart=/usr/bin/node /opt/app/src/index.js
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

**Using the PM2 Ecosystem configuration file:**
```javascript
// ecosystem.config.js
module.exports = {
  apps: [{
    name: 'api',
    script: 'src/index.js',
    instances: 'max',
    exec_mode: 'cluster',
    env_production: {
      NODE_ENV: 'production',
      PORT: 3000
    }
  }]
};
```

```bash
pm2 start ecosystem.config.js --env production
```

---

## FastAPI Deployment

### Gunicorn + Uvicorn Workers

Uvicorn is an ASGI server, and Gunicorn manages multiple worker processes. Together, they are well-suited for production environments.

**Why use Gunicorn + Uvicorn:**
- Uvicorn: high-performance ASGI server with async support
- Gunicorn: mature process manager with support for graceful restarts and shutdowns
- Multiple worker processes fully utilize multi-core CPUs

**Startup command:**
```bash
gunicorn app.main:app \
  -w 4 \
  -k uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:8000 \
  --access-logfile - \
  --error-logfile - \
  --log-level info
```

**Worker count recommendations:**
- Formula: (2 x number of CPU cores) + 1
- 4-core server: 9 workers
- 2-core server: 5 workers

**systemd service configuration:**
```ini
# /etc/systemd/system/fastapi.service
[Unit]
Description=FastAPI Application
After=network.target

[Service]
Type=notify
User=deploy
WorkingDirectory=/opt/app
ExecStart=/opt/app/venv/bin/gunicorn app.main:app \
  -w 4 \
  -k uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

### Docker Deployment

**Dockerfile (using the Dockerfile.python template):**
```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

EXPOSE 8000

CMD ["gunicorn", "app.main:app", \
     "-w", "4", \
     "-k", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000"]

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1
```

---

## Django Deployment

### Gunicorn

Django uses the WSGI protocol and runs through Gunicorn.

**Startup command:**
```bash
gunicorn myproject.wsgi:application \
  --bind 0.0.0.0:8000 \
  --workers 3 \
  --timeout 120 \
  --access-logfile - \
  --error-logfile -
```

**Pre-deployment preparation:**
```bash
# Collect static files
python manage.py collectstatic --noinput

# Run database migrations
python manage.py migrate --noinput
```

**Nginx configuration highlights:**
- Static files are served directly by Nginx (`STATIC_ROOT`)
- Media files are served directly by Nginx (`MEDIA_ROOT`)
- Dynamic requests are forwarded to Gunicorn via reverse proxy

### Docker Deployment

**Entrypoint script (entrypoint.sh):**
```bash
#!/bin/bash
set -e

echo "Running database migrations..."
python manage.py migrate --noinput

echo "Collecting static files..."
python manage.py collectstatic --noinput

echo "Starting Gunicorn..."
exec gunicorn myproject.wsgi:application \
  --bind 0.0.0.0:8000 \
  --workers 3
```

**Docker Compose volume mounts:**
```yaml
volumes:
  - static_data:/app/staticfiles
  - media_data:/app/mediafiles
```

---

## API Health Check Endpoint

All API services should implement a health check endpoint that returns 200 OK.

**What to check:**
- Database connection status
- Cache connection status (Redis, etc.)
- External service availability (if dependencies exist)
- Application version number

**Response example:**
```json
{
  "status": "healthy",
  "database": "connected",
  "cache": "connected",
  "version": "1.0.0",
  "uptime": 86400
}
```

**FastAPI implementation:**
```python
@app.get("/health")
async def health_check():
    return {"status": "healthy", "version": "1.0.0"}
```

**Express implementation:**
```javascript
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', version: '1.0.0' });
});
```

---

## API Documentation

- **FastAPI**: Auto-generated; access `/docs` (Swagger UI) and `/redoc` (ReDoc)
- **Express**: Use `swagger-ui-express` and `swagger-jsdoc` to generate documentation
- **Django**: Use `drf-spectacular` or `drf-yasg` to auto-generate OpenAPI documentation
