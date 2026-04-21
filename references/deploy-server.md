# 传统云服务器部署指南

本文档涵盖使用 Nginx、systemd、SSH 在传统云服务器上部署 Web 应用的完整流程。

---

## Nginx 反向代理配置

### 为什么需要反向代理

- **SSL 终止**：统一处理 HTTPS 证书，后端服务无需关心加密
- **负载均衡**：多实例分发请求，提升可用性
- **静态文件缓存**：Nginx 直接处理静态资源，减轻后端压力
- **安全头注入**：统一添加安全相关 HTTP 响应头
- **Gzip 压缩**：减少传输体积，加快页面加载

### 基础配置结构

```nginx
# /etc/nginx/conf.d/myapp.conf

upstream backend {
    server 127.0.0.1:3000;      # Node.js 应用
    # server 127.0.0.1:3001;   # 可添加更多实例实现负载均衡
    keepalive 32;
}

server {
    listen 80;
    server_name example.com www.example.com;

    # HTTP 重定向到 HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name example.com www.example.com;

    # SSL 证书配置（Let's Encrypt）
    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # 安全响应头
    add_header X-Content-Type-Options  "nosniff" always;
    add_header X-Frame-Options         "SAMEORIGIN" always;
    add_header X-XSS-Protection        "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;

    # Gzip 压缩
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml;
    gzip_min_length 1000;

    # 静态文件（带缓存）
    location /static/ {
        alias /var/www/myapp/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # 反向代理到后端
    location / {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket 支持
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
```

### 多站点配置

每个域名使用独立的配置文件，放在 `/etc/nginx/conf.d/` 下：

```
/etc/nginx/conf.d/
├── site-a.conf
├── site-b.conf
└── site-c.conf
```

### 测试与重载

```bash
# 检查配置语法
sudo nginx -t

# 重载配置（不中断服务）
sudo systemctl reload nginx
```

---

## systemd 服务配置

### 为什么使用 systemd

- **进程守护**：应用崩溃后自动重启
- **开机自启**：服务器重启后自动拉起服务
- **日志管理**：通过 `journalctl` 统一查看日志
- **资源控制**：可限制 CPU、内存等资源

### Node.js 应用服务

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

### Python 应用服务（Gunicorn）

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

### Python 应用服务（Uvicorn）

```ini
ExecStart=/var/www/myapp/venv/bin/uvicorn \
    --workers 4 \
    --host 127.0.0.1 \
    --port 8000 \
    app:app
```

### 常用管理命令

```bash
# 加载新服务文件
sudo systemctl daemon-reload

# 启用并立即启动（开机自启 + 立即运行）
sudo systemctl enable --now myapp

# 查看服务状态
sudo systemctl status myapp

# 重启服务
sudo systemctl restart myapp

# 停止服务
sudo systemctl stop myapp

# 查看实时日志
sudo journalctl -u myapp -f

# 查看最近 100 行日志
sudo journalctl -u myapp -n 100
```

### 使用 PM2（Node.js 替代方案）

```bash
# 安装 PM2
npm install -g pm2

# 启动应用
pm2 start server.js --name myapp

# 生成 systemd 服务（实现开机自启）
pm2 startup
pm2 save
```

---

## SSH 远程部署

### 密钥认证配置

```bash
# 生成密钥对（本地执行）
ssh-keygen -t ed25519 -C "deploy"

# 复制公钥到服务器
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@your-server-ip

# 验证免密登录
ssh user@your-server-ip "echo OK"
```

### 文件同步（rsync）

```bash
# 同步项目文件到服务器，排除不需要的目录
rsync -avz --delete \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='venv' \
    --exclude='__pycache__' \
    --exclude='.env' \
    ./ user@your-server-ip:/var/www/myapp/
```

### 远程命令执行

```bash
# 在服务器上执行单条命令
ssh user@your-server-ip "cd /var/www/myapp && npm install && npm run build"

# 执行多条命令
ssh user@your-server-ip "bash -s" << 'EOF'
cd /var/www/myapp
npm install --production
npm run build
sudo systemctl restart myapp
EOF
```

### 自动化部署脚本

```bash
#!/bin/bash
# deploy.sh - 项目根目录下执行

SERVER="user@your-server-ip"
REMOTE_DIR="/var/www/myapp"
SERVICE_NAME="myapp"

echo ">>> 同步文件..."
rsync -avz --delete \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='venv' \
    --exclude='__pycache__' \
    --exclude='.env' \
    ./ ${SERVER}:${REMOTE_DIR}/

echo ">>> 远程构建..."
ssh ${SERVER} "bash -s" << EOF
cd ${REMOTE_DIR}
npm install --production
npm run build
sudo systemctl restart ${SERVICE_NAME}
sudo systemctl status ${SERVICE_NAME} --no-pager
EOF

echo ">>> 部署完成"
```

---

## 防火墙配置

使用 UFW（Ubuntu 默认防火墙）：

```bash
# 允许 SSH（重要：先放行 SSH，避免锁死）
sudo ufw allow OpenSSH

# 允许 HTTP 和 HTTPS（Nginx Full 预设规则）
sudo ufw allow 'Nginx Full'

# 启用防火墙
sudo ufw enable

# 查看防火墙状态
sudo ufw status verbose

# 输出示例：
# Status: active
# To                         Action      From
# --                         ------      ----
# OpenSSH                    ALLOW       Anywhere
# Nginx Full                 ALLOW       Anywhere
```

---

## 日志管理

### Nginx 日志

```bash
# 访问日志
sudo tail -f /var/log/nginx/access.log

# 错误日志
sudo tail -f /var/log/nginx/error.log

# 按域名过滤（如果配置了独立日志）
# 在 server 块中添加：
#   access_log /var/log/nginx/myapp_access.log;
#   error_log  /var/log/nginx/myapp_error.log;
```

### 应用日志

```bash
# systemd 服务日志（实时跟踪）
sudo journalctl -u myapp -f

# 查看今天的日志
sudo journalctl -u myapp --since today

# 查看最近 1 小时的日志
sudo journalctl -u myapp --since "1 hour ago"

# 导出日志到文件
sudo journalctl -u myapp --since today > myapp.log
```

### 日志轮转

Nginx 和 journald 通常已预配置日志轮转，无需额外设置：

- **Nginx**：`/etc/logrotate.d/nginx` 默认按天轮转，保留 14 天
- **journald**：`/etc/systemd/journald.conf` 中 `SystemMaxUse` 控制最大占用空间

如需自定义应用日志轮转：

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
