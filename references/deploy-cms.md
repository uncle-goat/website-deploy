# CMS Deployment Guide

## WordPress Docker Deployment

### Architecture

WordPress uses the classic LEMP architecture, with services orchestrated via Docker Compose:

```
Nginx (Reverse Proxy + SSL Termination)
  ├── WordPress (PHP-FPM)
  ├── MySQL 8.0
  └── Redis 7 (Object Cache)
```

Use the `docker-compose.cms` template to quickly generate the configuration.

### Configuration Highlights

**Core docker-compose.yml configuration:**

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

**Image selection notes:**
- `wordpress:6.5-php8.2-fpm-alpine` — PHP-FPM mode, used with Nginx; the Alpine base image is smaller in size
- `mysql:8.0` — Stable version with support for JSON fields and window functions
- `redis:7-alpine` — Used for WordPress object caching, significantly reducing database queries

**Nginx configuration highlights (PHP-FPM proxy):**

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

### Deployment Steps

**1. Generate configuration files:**

```bash
# Generate docker-compose.yml from the template
# Create a .env file
cat > .env << 'EOF'
DB_NAME=wordpress
DB_USER=wp_user
DB_PASSWORD=your_strong_password
DB_ROOT_PASSWORD=your_root_password
EOF
```

**2. Start the services:**

```bash
docker compose up -d
```

**3. Complete the WordPress installation:**

- Visit `http://your-domain/wp-admin`
- Follow the wizard to set up site information and the admin account
- Log in to the admin dashboard after installation is complete

**4. Configure Redis object caching:**

```bash
# Install the Redis Object Cache plugin
# Add Redis configuration to wp-config.php
define('WP_REDIS_HOST', 'redis');
define('WP_REDIS_PORT', 6379);
define('WP_CACHE', true);
```

**5. Verify the Redis connection:**

In the WordPress admin dashboard, go to Settings → Redis and click "Enable Object Cache." The status should show as "Connected."

### Backup Strategy

**Database backup:**

```bash
# Manual backup
docker exec db-container mysqldump \
  -u root -p"${DB_ROOT_PASSWORD}" wordpress > backup_$(date +%Y%m%d).sql

# Restore
docker exec -i db-container mysql \
  -u root -p"${DB_ROOT_PASSWORD}" wordpress < backup.sql
```

**File backup:**

```bash
# Back up the wp-content directory (themes, plugins, uploads)
docker run --rm -v wordpress-data:/data -v $(pwd):/backup \
  alpine tar -czf /backup/wp-content-backup-$(date +%Y%m%d).tar.gz -C /data .
```

**Automated backups (Cron):**

```bash
# Back up the database every day at 2:00 AM
0 2 * * * docker exec db-container mysqldump -u root -p'password' wordpress > /backups/db/daily_$(date +\%Y\%m\%d).sql

# Back up files every Sunday at 3:00 AM
0 3 * * 0 docker run --rm -v wordpress-data:/data -v /backups/files:/backup alpine tar -czf /backup/wp-content-weekly_$(date +\%Y\%m\%d).tar.gz -C /data .

# Retain only the last 30 days of database backups
0 4 * * * find /backups/db -name "daily_*.sql" -mtime +30 -delete
```

---

## Ghost Docker Deployment

### Architecture

Ghost is a modern CMS built on Node.js, with a lighter deployment footprint than WordPress:

```
Ghost (Node.js)
  └── MySQL 8.0 / SQLite
```

### Configuration Highlights

**docker-compose.yml:**

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

**Key configuration notes:**
- `ghost:5-alpine` — Official Alpine image with a small footprint
- `url` — Must be set to the final domain name, otherwise resource loading will fail
- `database__client` — Supports `mysql` and `sqlite3`; MySQL is recommended for production
- `mail` — Configure an SMTP service (Mailgun, SendGrid, etc.) for sending system emails

**config.production.json (optional, takes priority over environment variables):**

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

### Deployment Steps

**1. Generate configuration files:**

```bash
# Create a .env file
cat > .env << 'EOF'
DB_NAME=ghost_production
DB_USER=ghost
DB_PASSWORD=your_strong_password
DB_ROOT_PASSWORD=your_root_password
MAIL_USER=postmaster@your-domain.com
MAIL_PASSWORD=your-mail-password
EOF
```

**2. Start the services:**

```bash
docker compose up -d
```

**3. Initialize the admin dashboard:**

- Visit `http://your-domain/ghost`
- Create an admin account
- Invite team members (optional)

**4. Configure Nginx reverse proxy (recommended):**

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

## Security Hardening

### WordPress Security

**Limit login attempts:**
- Install the `Limit Login Attempts Reloaded` or `Wordfence Security` plugin
- Set a maximum number of failed login attempts (recommended: 3-5)
- Configure a lockout duration (recommended: 15-30 minutes)

**Disable file editing in the admin dashboard:**

Add the following to `wp-config.php`:

```php
define('DISALLOW_FILE_EDIT', true);
define('DISALLOW_FILE_MODS', true);  // Prevents installing/updating plugins and themes
```

**Regular updates:**
- Keep the WordPress core, plugins, and themes up to date
- Enable automatic updates for minor versions: `add_filter('auto_update_core', '__return_true');`
- Always back up the database and files before updating

**Other security measures:**
- Delete the default `admin` user and create a new admin account
- Use strong passwords (16+ characters, with uppercase and lowercase letters, numbers, and special characters)
- Enable two-factor authentication (the `Wordfence Login Security` plugin is recommended)
- Change the wp-login.php path (via a plugin or Nginx rewrite rules)
- Hide the WordPress version number: `remove_action('wp_head', 'wp_generator');`

### Ghost Security

- Ghost has built-in security mechanisms, including automatic HTTPS redirects
- Update Ghost regularly: `docker compose pull && docker compose up -d`
- Configure strong passwords and two-factor authentication (Ghost admin → Settings → Staff)
- Use Nginx to rate-limit access to `/ghost/api/admin`
- Regularly back up the database and the content directory
