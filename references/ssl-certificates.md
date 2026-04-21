# SSL Certificate Configuration Guide

## Let's Encrypt + certbot

### Why Choose Let's Encrypt

- **Free**: No fees whatsoever, permanently free to use
- **Automated**: Supports automatic certificate issuance and renewal, reducing operational overhead
- **Trusted**: Trusted by all major browsers, with root certificates widely pre-installed
- **Versatile**: Supports single-domain, multi-domain (SAN), and wildcard certificates

### Installing certbot

```bash
# Ubuntu / Debian
apt update && apt install -y certbot python3-certbot-nginx

# CentOS / RHEL
yum install -y epel-release && yum install -y certbot python3-certbot-nginx
```

### Four Modes for Obtaining Certificates

#### 1. --nginx Mode (Recommended)

certbot automatically modifies the Nginx configuration. This is the simplest approach. Requires Nginx to be properly configured and listening on port 80.

```bash
certbot --nginx -d example.com -d www.example.com
```

After execution, certbot will automatically:
- Verify domain ownership
- Obtain the certificate and save it to `/etc/letsencrypt/live/example.com/`
- Modify the Nginx configuration to add SSL-related directives
- Configure a 301 redirect from HTTP to HTTPS

#### 2. --standalone Mode

certbot starts its own temporary web server listening on port 80. Suitable when Nginx is not yet configured.

```bash
# First, stop the service occupying port 80
systemctl stop nginx
# Obtain the certificate
certbot certonly --standalone -d example.com
# Restart Nginx
systemctl start nginx
```

#### 3. --webroot Mode

certbot uses the document root of an existing web server to place verification files. Suitable when you do not want to interrupt existing services.

```bash
certbot certonly --webroot -w /var/www/html -d example.com
```

#### 4. --dns Mode

Uses the DNS-01 challenge method. Suitable when port 80 is blocked by a firewall or is otherwise inaccessible.

```bash
certbot certonly --manual --preferred-challenges dns -d example.com
```

After execution, you need to manually add the specified TXT record to your DNS configuration, wait for it to take effect, and then press Enter to continue.

### Wildcard Certificates

Wildcard certificates can only be obtained via the DNS-01 challenge method:

```bash
certbot certonly --manual --preferred-challenges dns -d "*.example.com" -d "example.com"
```

> Note: Each renewal requires manually adding a DNS TXT record. It is recommended to use a DNS API plugin for automation.

---

## Automatic Renewal

### Testing Renewal

```bash
# First, test with a dry-run to ensure the renewal process works correctly
certbot renew --dry-run
```

### Cron Scheduled Task

```bash
# Edit crontab
crontab -e

# Add the following line: check and renew every day at 3:00 AM, reload Nginx after successful renewal
0 3 * * * certbot renew --quiet --deploy-hook "systemctl reload nginx"
```

### systemd Timer

After installing certbot, `certbot.timer` is typically enabled automatically. You can verify this with the following commands:

```bash
systemctl status certbot.timer
systemctl list-timers | grep certbot
```

If it is not enabled:

```bash
systemctl enable certbot.timer
systemctl start certbot.timer
```

---

## Nginx SSL Configuration

Below is the recommended SSL configuration for production environments:

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

    # Protocol versions
    ssl_protocols TLSv1.2 TLSv1.3;

    # Cipher suites (modern recommended configuration)
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;

    # HSTS: force browsers to use HTTPS (1-year validity, includes subdomains)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # OCSP Stapling: reduces client verification latency
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem;
    resolver 8.8.8.8 8.8.4.4 valid=300s;

    # SSL session cache
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    root /var/www/html;
    index index.html;
}
```

---

## Common Troubleshooting

### Certificate Issuance Failure

1. **DNS resolution issues**: Confirm that the domain's A record correctly points to the server IP
   ```bash
   dig example.com +short
   ```
2. **Port 80 unreachable**: Check whether the firewall allows ports 80 and 443
   ```bash
   ufw allow 80/tcp && ufw allow 443/tcp
   ```
3. **Nginx configuration errors**: Check the Nginx configuration syntax
   ```bash
   nginx -t
   ```

### Certificate Renewal Failure

- Check the certbot logs to identify the cause:
  ```bash
  cat /var/log/letsencrypt/letsencrypt.log
  ```
- Common causes: DNS record changes, server port unreachable, insufficient disk space

### Mixed Content

Browsers will block HTTP resources loaded within an HTTPS page. Troubleshooting steps:

- Use the browser developer tools (F12) → Console to check for mixed content warnings
- Search and replace `http://` with `https://` across the entire site
- You can add a CSP header in Nginx to help detect mixed content:
  ```nginx
  add_header Content-Security-Policy "upgrade-insecure-requests" always;
  ```

### Certificate Not Trusted

- Check whether you are using the full certificate chain (`fullchain.pem` instead of `cert.pem`)
- Confirm that the intermediate certificate is correctly configured; Let's Encrypt's `chain.pem` contains the required intermediate certificate
- Use an online tool (such as SSL Labs) to check the certificate chain integrity:
  ```
  https://www.ssllabs.com/ssltest/analyze.html?d=example.com
  ```
