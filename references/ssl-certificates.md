# SSL 证书配置指南

## Let's Encrypt + certbot

### 为什么选择 Let's Encrypt

- **免费**：无需支付任何费用，永久免费使用
- **自动化**：支持自动申请和续期，减少运维负担
- **可信**：受所有主流浏览器信任，根证书已被广泛预装
- **通用**：支持单域名、多域名（SAN）和通配符证书

### 安装 certbot

```bash
# Ubuntu / Debian
apt update && apt install -y certbot python3-certbot-nginx

# CentOS / RHEL
yum install -y epel-release && yum install -y certbot python3-certbot-nginx
```

### 获取证书的四种模式

#### 1. --nginx 模式（推荐）

certbot 自动修改 Nginx 配置，最简单的方式。要求 Nginx 已正确配置且监听 80 端口。

```bash
certbot --nginx -d example.com -d www.example.com
```

执行后 certbot 会自动：
- 验证域名所有权
- 获取证书并保存到 `/etc/letsencrypt/live/example.com/`
- 修改 Nginx 配置，添加 SSL 相关指令
- 配置 HTTP 到 HTTPS 的 301 重定向

#### 2. --standalone 模式

certbot 启动自身的临时 Web 服务器监听 80 端口。适用于 Nginx 尚未配置的情况。

```bash
# 先停止占用 80 端口的服务
systemctl stop nginx
# 获取证书
certbot certonly --standalone -d example.com
# 重新启动 Nginx
systemctl start nginx
```

#### 3. --webroot 模式

certbot 利用现有 Web 服务器的文档根目录放置验证文件。适用于不希望中断现有服务的情况。

```bash
certbot certonly --webroot -w /var/www/html -d example.com
```

#### 4. --dns 模式

使用 DNS-01 验证方式，适用于 80 端口被防火墙阻断或无法访问的场景。

```bash
certbot certonly --manual --preferred-challenges dns -d example.com
```

执行后需要手动添加指定的 TXT 记录到 DNS 配置中，等待生效后按回车继续。

### 通配符证书

通配符证书仅支持通过 DNS-01 验证方式获取：

```bash
certbot certonly --manual --preferred-challenges dns -d "*.example.com" -d "example.com"
```

> 注意：每次续期时都需要手动添加 DNS TXT 记录，建议配合 DNS API 插件实现自动化。

---

## 自动续期

### 测试续期

```bash
# 先用 dry-run 测试，确保续期流程正常
certbot renew --dry-run
```

### Cron 定时任务

```bash
# 编辑 crontab
crontab -e

# 添加以下行：每天凌晨 3 点检查并续期，续期成功后重载 Nginx
0 3 * * * certbot renew --quiet --deploy-hook "systemctl reload nginx"
```

### systemd timer

certbot 安装后通常会自动启用 `certbot.timer`，可通过以下命令确认：

```bash
systemctl status certbot.timer
systemctl list-timers | grep certbot
```

如未启用：

```bash
systemctl enable certbot.timer
systemctl start certbot.timer
```

---

## Nginx SSL 配置

以下为推荐的生产环境 SSL 配置：

```nginx
server {
    listen 80;
    server_name example.com www.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name example.com www.example.com;

    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    # 协议版本
    ssl_protocols TLSv1.2 TLSv1.3;

    # 加密套件（现代推荐配置）
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;

    # HSTS：强制浏览器使用 HTTPS（有效期 1 年，包含子域名）
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # OCSP Stapling：减少客户端验证延迟
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem;
    resolver 8.8.8.8 8.8.4.4 valid=300s;

    # SSL 会话缓存
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    root /var/www/html;
    index index.html;
}
```

---

## 常见问题排查

### 证书获取失败

1. **DNS 解析问题**：确认域名 A 记录已正确指向服务器 IP
   ```bash
   dig example.com +short
   ```
2. **80 端口不可达**：检查防火墙是否放行 80 和 443 端口
   ```bash
   ufw allow 80/tcp && ufw allow 443/tcp
   ```
3. **Nginx 配置错误**：检查 Nginx 配置语法
   ```bash
   nginx -t
   ```

### 证书续期失败

- 查看 certbot 日志定位原因：
  ```bash
  cat /var/log/letsencrypt/letsencrypt.log
  ```
- 常见原因：DNS 记录变更、服务器端口不通、磁盘空间不足

### 混合内容（Mixed Content）

浏览器会阻止 HTTPS 页面中加载 HTTP 资源。排查方法：

- 使用浏览器开发者工具（F12）-> Console 查看混合内容警告
- 全站搜索替换 `http://` 为 `https://`
- Nginx 中可添加 CSP 头辅助检测：
  ```nginx
  add_header Content-Security-Policy "upgrade-insecure-requests" always;
  ```

### 证书不受信任

- 检查是否使用了完整的证书链（`fullchain.pem` 而非 `cert.pem`）
- 确认中间证书已正确配置，Let's Encrypt 的 `chain.pem` 包含所需的中间证书
- 使用在线工具（如 SSL Labs）检测证书链完整性：
  ```
  https://www.ssllabs.com/ssltest/analyze.html?d=example.com
  ```
