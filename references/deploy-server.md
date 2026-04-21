# Traditional Cloud Server Deployment Guide

This document covers the complete workflow for deploying web applications on traditional cloud servers using Nginx, systemd, and SSH.

---

## Nginx Reverse Proxy Configuration

### Why You Need a Reverse Proxy

- **SSL termination:** Centrally handles HTTPS certificates; backend services do not need to handle encryption
- **Load balancing:** Distributes requests across multiple instances, improving availability
- **Static file caching:** Nginx serves static resources directly, reducing backend load
- **Security header injection:** Uniformly adds security-related HTTP response headers
- **Gzip compression:** Reduces transfer size and speeds up page loading

### Basic Configuration Structure

```nginx
# /etc/nginx/conf.d/myapp.conf

upstream backend {
    server 127.0.0.1:3000;      # Node.js application
    # server 127.0.0.1:3001;   # Add more instances for load balancing
    keepalive 32;
}

server {
    listen 80;
    server_name example.com www.example.com;

    # Redirect HTTP to HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name example.com www.example.com;

    # SSL certificate configuration (Let's Encrypt)
    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # Security response headers
    add_header X-Content-Type-Options  "nosniff" always;
    add_header X-Frame-Options         "SAMEORIGIN" always;
    add_header X-XSS-Protection        "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml;
    gzip_min_length 1000;

    # Static files (with caching)
    location /static/ {
        alias /var/www/myapp/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Reverse proxy to backend
    location / {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
```

### Multi-Site Configuration

Each domain uses a separate configuration file, placed under `/etc/nginx/conf.d/`:

```
/etc/nginx/conf.d/
├── site-a.conf
├── site-b.conf
└── site-c.conf
```

### Testing and Reloading

```bash
# Check configuration syntax
sudo nginx -t

# Reload configuration (without interrupting service)
sudo systemctl reload nginx
```

---

## systemd Service Configuration

### Why Use systemd

- **Process supervision:** Automatically restarts the application after a crash
- **Start on boot:** Automatically starts the service after a server reboot
- **Log management:** Centrally view logs via `journalctl`
- **Resource control:** Can limit CPU, memory, and other resources

### Node.js Application Service

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My Node.js Application
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/var/www/myapp
ExecStart=/usr/bin/node /var/www/myapp/server.js
Restart=always
RestartSec=5
EnvironmentFile=/var/www/myapp/.env
StandardOutput=journal
StandardError=journal
SyslogIdentifier=myapp

[Install]
WantedBy=multi-user.target
```

### Python Application Service (Gunicorn)

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My Python Application
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/var/www/myapp
ExecStart=/var/www/myapp/venv/bin/gunicorn \
    --workers 4 \
    --bind 127.0.0.1:8000 \
    --access-logfile - \
    --error-logfile - \
    app:app
Restart=always
RestartSec=5
EnvironmentFile=/var/www/myapp/.env

[Install]
WantedBy=multi-user.target
```

### Python Application Service (Uvicorn)

```ini
ExecStart=/var/www/myapp/venv/bin/uvicorn \
    --workers 4 \
    --host 127.0.0.1 \
    --port 8000 \
    app:app
```

### Common Management Commands

```bash
# Reload new service files
sudo systemctl daemon-reload

# Enable and start immediately (start on boot + run now)
sudo systemctl enable --now myapp

# View service status
sudo systemctl status myapp

# Restart service
sudo systemctl restart myapp

# Stop service
sudo systemctl stop myapp

# View real-time logs
sudo journalctl -u myapp -f

# View the last 100 lines of logs
sudo journalctl -u myapp -n 100
```

### Using PM2 (Node.js Alternative)

```bash
# Install PM2
npm install -g pm2

# Start application
pm2 start server.js --name myapp

# Generate systemd service (for start on boot)
pm2 startup
pm2 save
```

---

## SSH Remote Deployment

### Key Authentication Configuration

```bash
# Generate a key pair (run locally)
ssh-keygen -t ed25519 -C "deploy"

# Copy public key to the server
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@your-server-ip

# Verify passwordless login
ssh user@your-server-ip "echo OK"
```

### File Synchronization (rsync)

```bash
# Sync project files to the server, excluding unnecessary directories
rsync -avz --delete \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='venv' \
    --exclude='__pycache__' \
    --exclude='.env' \
    ./ user@your-server-ip:/var/www/myapp/
```

### Remote Command Execution

```bash
# Execute a single command on the server
ssh user@your-server-ip "cd /var/www/myapp && npm install && npm run build"

# Execute multiple commands
ssh user@your-server-ip "bash -s" << 'EOF'
cd /var/www/myapp
npm install --production
npm run build
sudo systemctl restart myapp
EOF
```

### Automated Deployment Script

```bash
#!/bin/bash
# deploy.sh - Run from the project root directory

SERVER="user@your-server-ip"
REMOTE_DIR="/var/www/myapp"
SERVICE_NAME="myapp"

echo ">>> Syncing files..."
rsync -avz --delete \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='venv' \
    --exclude='__pycache__' \
    --exclude='.env' \
    ./ ${SERVER}:${REMOTE_DIR}/

echo ">>> Remote build..."
ssh ${SERVER} "bash -s" << EOF
cd ${REMOTE_DIR}
npm install --production
npm run build
sudo systemctl restart ${SERVICE_NAME}
sudo systemctl status ${SERVICE_NAME} --no-pager
EOF

echo ">>> Deployment complete"
```

---

## Firewall Configuration

Using UFW (Ubuntu's default firewall):

```bash
# Allow SSH (important: allow SSH first to avoid lockout)
sudo ufw allow OpenSSH

# Allow HTTP and HTTPS (Nginx Full preset rule)
sudo ufw allow 'Nginx Full'

# Enable the firewall
sudo ufw enable

# View firewall status
sudo ufw status verbose

# Example output:
# Status: active
# To                         Action      From
# --                         ------      ----
# OpenSSH                    ALLOW       Anywhere
# Nginx Full                 ALLOW       Anywhere
```

---

## Log Management

### Nginx Logs

```bash
# Access log
sudo tail -f /var/log/nginx/access.log

# Error log
sudo tail -f /var/log/nginx/error.log

# Filter by domain (if separate logs are configured)
# Add to the server block:
#   access_log /var/log/nginx/myapp_access.log;
#   error_log  /var/log/nginx/myapp_error.log;
```

### Application Logs

```bash
# systemd service logs (real-time tracking)
sudo journalctl -u myapp -f

# View today's logs
sudo journalctl -u myapp --since today

# View logs from the last hour
sudo journalctl -u myapp --since "1 hour ago"

# Export logs to a file
sudo journalctl -u myapp --since today > myapp.log
```

### Log Rotation

Nginx and journald typically have log rotation pre-configured and require no additional setup:

- **Nginx:** `/etc/logrotate.d/nginx` rotates daily by default, keeping 14 days
- **journald:** `SystemMaxUse` in `/etc/systemd/journald.conf` controls the maximum disk usage

For custom application log rotation:

```ini
# /etc/logrotate.d/myapp
/var/log/myapp/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
```
