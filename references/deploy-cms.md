# CMS 部署指南

## WordPress Docker 部署

### 架构

WordPress 采用经典的 LEMP 架构，通过 Docker Compose 编排各服务：

```
Nginx (反向代理 + SSL 终端)
  ├── WordPress (PHP-FPM)
  ├── MySQL 8.0
  └── Redis 7 (对象缓存)
```

使用 `docker-compose.cms` 模板快速生成配置。

### 配置要点

**docker-compose.yml 核心配置：**

```yaml
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/ssl:/etc/nginx/ssl
      - wordpress-data:/var/www/html
    depends_on:
      - wordpress
    restart: unless-stopped

  wordpress:
    image: wordpress:6.5-php8.2-fpm-alpine
    volumes:
      - wordpress-data:/var/www/html
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: ${DB_USER}
      WORDPRESS_DB_PASSWORD: ${DB_PASSWORD}
      WORDPRESS_DB_NAME: ${DB_NAME}
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: mysql:8.0
    environment:
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
    volumes:
      - db-data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    volumes:
      - redis-data:/data
    restart: unless-stopped

volumes:
  wordpress-data:
  db-data:
  redis-data:
```

**镜像选择说明：**
- `wordpress:6.5-php8.2-fpm-alpine` — PHP-FPM 模式，配合 Nginx 使用，Alpine 基础镜像体积更小
- `mysql:8.0` — 稳定版本，支持 JSON 字段和窗口函数
- `redis:7-alpine` — 用于 WordPress 对象缓存，大幅减少数据库查询

**Nginx 配置要点（PHP-FPM 代理）：**

```nginx
upstream php-fpm {
    server wordpress:9000;
}

server {
    listen 80;
    server_name example.com;
    root /var/www/html;

    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        fastcgi_pass php-fpm;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?)$ {
        expires 365d;
        access_log off;
    }
}
```

### 部署步骤

**1. 生成配置文件：**

```bash
# 从模板生成 docker-compose.yml
# 创建 .env 文件
cat > .env << 'EOF'
DB_NAME=wordpress
DB_USER=wp_user
DB_PASSWORD=your_strong_password
DB_ROOT_PASSWORD=your_root_password
EOF
```

**2. 启动服务：**

```bash
docker compose up -d
```

**3. 完成 WordPress 安装：**

- 访问 `http://your-domain/wp-admin`
- 按照向导完成站点信息、管理员账号设置
- 安装完成后登录后台

**4. 配置 Redis 对象缓存：**

```bash
# 安装 Redis Object Cache 插件
# 在 wp-config.php 中添加 Redis 配置
define('WP_REDIS_HOST', 'redis');
define('WP_REDIS_PORT', 6379);
define('WP_CACHE', true);
```

**5. 验证 Redis 连接：**

在 WordPress 后台 → 设置 → Redis 中点击"启用对象缓存"，状态应显示为"已连接"。

### 备份策略

**数据库备份：**

```bash
# 手动备份
docker exec db-container mysqldump \
  -u root -p"${DB_ROOT_PASSWORD}" wordpress > backup_$(date +%Y%m%d).sql

# 恢复
docker exec -i db-container mysql \
  -u root -p"${DB_ROOT_PASSWORD}" wordpress < backup.sql
```

**文件备份：**

```bash
# 备份 wp-content 目录（主题、插件、上传文件）
docker run --rm -v wordpress-data:/data -v $(pwd):/backup \
  alpine tar -czf /backup/wp-content-backup-$(date +%Y%m%d).tar.gz -C /data .
```

**自动化备份（Cron）：**

```bash
# 每天凌晨 2 点备份数据库
0 2 * * * docker exec db-container mysqldump -u root -p'password' wordpress > /backups/db/daily_$(date +\%Y\%m\%d).sql

# 每周日凌晨 3 点备份文件
0 3 * * 0 docker run --rm -v wordpress-data:/data -v /backups/files:/backup alpine tar -czf /backup/wp-content-weekly_$(date +\%Y\%m\%d).tar.gz -C /data .

# 保留最近 30 天的数据库备份
0 4 * * * find /backups/db -name "daily_*.sql" -mtime +30 -delete
```

---

## Ghost Docker 部署

### 架构

Ghost 是基于 Node.js 的现代 CMS，部署比 WordPress 更轻量：

```
Ghost (Node.js)
  └── MySQL 8.0 / SQLite
```

### 配置要点

**docker-compose.yml：**

```yaml
version: '3.8'

services:
  ghost:
    image: ghost:5-alpine
    ports:
      - "2368:2368"
    volumes:
      - ghost-data:/var/lib/ghost/content
    environment:
      url: https://your-domain.com
      database__client: mysql
      database__connection__host: db
      database__connection__user: ${DB_USER}
      database__connection__password: ${DB_PASSWORD}
      database__connection__database: ${DB_NAME}
      mail__transport: SMTP
      mail__options__service: Mailgun
      mail__options__auth__user: ${MAIL_USER}
      mail__options__auth__pass: ${MAIL_PASSWORD}
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: mysql:8.0
    environment:
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
    volumes:
      - db-data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

volumes:
  ghost-data:
  db-data:
```

**关键配置说明：**
- `ghost:5-alpine` — 官方 Alpine 镜像，体积小
- `url` — 必须设置为最终访问域名，否则资源加载会出错
- `database__client` — 支持 `mysql` 和 `sqlite3`，生产环境推荐 MySQL
- `mail` — 配置 SMTP 服务（Mailgun、SendGrid 等）用于发送系统邮件

**config.production.json（可选，优先级高于环境变量）：**

```json
{
  "url": "https://your-domain.com",
  "server": {
    "port": 2368,
    "host": "0.0.0.0"
  },
  "database": {
    "client": "mysql",
    "connection": {
      "host": "db",
      "user": "ghost",
      "password": "your_password",
      "database": "ghost_production"
    }
  },
  "mail": {
    "transport": "SMTP",
    "options": {
      "service": "Mailgun",
      "auth": {
        "user": "postmaster@your-domain.com",
        "pass": "your-mail-password"
      }
    }
  },
  "logging": {
    "transports": ["stdout"]
  }
}
```

### 部署步骤

**1. 生成配置文件：**

```bash
# 创建 .env
cat > .env << 'EOF'
DB_NAME=ghost_production
DB_USER=ghost
DB_PASSWORD=your_strong_password
DB_ROOT_PASSWORD=your_root_password
MAIL_USER=postmaster@your-domain.com
MAIL_PASSWORD=your-mail-password
EOF
```

**2. 启动服务：**

```bash
docker compose up -d
```

**3. 初始化管理后台：**

- 访问 `http://your-domain/ghost`
- 创建管理员账号
- 邀请团队成员（可选）

**4. 配置 Nginx 反向代理（推荐）：**

```nginx
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:2368;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
```

---

## 安全加固

### WordPress 安全

**限制登录尝试：**
- 安装 `Limit Login Attempts Reloaded` 或 `Wordfence Security` 插件
- 设置最大登录失败次数（建议 3-5 次）
- 配置锁定时间（建议 15-30 分钟）

**禁用后台文件编辑：**

在 `wp-config.php` 中添加：

```php
define('DISALLOW_FILE_EDIT', true);
define('DISALLOW_FILE_MODS', true);  // 禁止安装/更新插件和主题
```

**定期更新：**
- WordPress 核心、插件、主题保持最新版本
- 启用自动更新（小版本）：`add_filter('auto_update_core', '__return_true');`
- 更新前务必备份数据库和文件

**其他安全措施：**
- 删除默认 `admin` 用户，创建新管理员账号
- 使用强密码（16 位以上，含大小写字母、数字、特殊字符）
- 启用双因素认证（推荐 `Wordfence Login Security` 插件）
- 修改 wp-login.php 路径（通过插件或 Nginx rewrite 规则）
- 隐藏 WordPress 版本号：`remove_action('wp_head', 'wp_generator');`

### Ghost 安全

- Ghost 内置了较好的安全机制，包括自动 HTTPS 重定向
- 定期更新 Ghost 版本：`docker compose pull && docker compose up -d`
- 配置强密码和双因素认证（Ghost 后台 → Settings → Staff）
- 使用 Nginx 限制 `/ghost/api/admin` 的访问频率
- 定期备份数据库和 content 目录
