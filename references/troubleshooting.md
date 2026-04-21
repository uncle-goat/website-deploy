# Troubleshooting Guide

## Docker Issues

### Build Failure
- **Check Dockerfile syntax**: Ensure instructions like FROM, RUN, COPY are spelled correctly; note case sensitivity
- **Check .dockerignore**: Exclude unnecessary files (.git, node_modules) to reduce build context size
- **Check network**: Building requires pulling base images and dependencies; ensure network connectivity
- **Check base image**: Confirm the base image tag exists, e.g., use `node:20-alpine` instead of `node:latest` (latest may be replaced)
- **Multi-stage builds**: For large projects, multi-stage builds are recommended to reduce final image size

### Container Exits Immediately After Starting
- **View logs**: `docker compose logs <service>` or `docker logs <container>`
- **Check CMD/ENTRYPOINT**: Ensure foreground execution; do not use `npm start` in background mode
- **Check environment variables**: Missing required environment variables may cause the program to crash
- **Check file permissions**: Verify that mounted files/directories have correct permissions
- **Check dependencies**: Ensure dependency services like databases are ready

### Network Connectivity Issues
- **Check network configuration**: `docker network ls` and `docker network inspect <network>`
- **Check service names**: Inter-container communication uses service names, not IP addresses (e.g., `http://db:5432`)
- **Check firewall**: Host firewall may block container port mappings
- **Use host network**: For debugging, use `network_mode: host` to rule out network issues

### Volume Mount Issues
- **Check paths**: Ensure host paths exist and are correct; note the difference between relative and absolute paths
- **Check permissions**: Verify that the container user (typically root) matches host file permissions
- **SELinux** (CentOS): Add `:z` or `:Z` suffix, e.g., `-v /data:/app:z`
- **Named volumes vs bind mounts**: Named volumes are recommended for production; bind mounts are acceptable for development

### Insufficient Disk Space
- **Clean unused resources**: `docker system prune -a` (remove all unused images, containers, networks)
- **Clean volumes**: `docker volume prune` (remove unused volumes; back up data first)
- **View usage**: `docker system df` to see space usage by component
- **Log limits**: Configure log driver and size limits in the compose file

---

## Nginx Issues

### 502 Bad Gateway
- **Upstream service not running**: Check backend service status with `systemctl status <service>`
- **Wrong port**: Confirm the port in proxy_pass matches the backend service
- **Socket permissions**: When using Unix sockets, ensure the Nginx user has read/write permissions
- **Timeout**: Increase `proxy_read_timeout` and `proxy_connect_timeout`

### 503 Service Unavailable
- **Upstream overloaded**: Backend service lacks capacity; increase worker count or use load balancing
- **Service not ready**: Check backend startup time and configure health checks
- **Rate limiting triggered**: Check if `limit_req` configuration is too strict

### 403 Forbidden
- **File permissions**: Ensure the Nginx user (www-data/nginx) has read permissions on files
- **Directory index**: Missing index file and `autoindex on` is not enabled
- **SELinux**: Temporarily disable with `setenforce 0` for testing, or configure the correct SELinux context
- **deny rules**: Check for `deny all` or other access control rules

### Configuration Syntax Errors
- **Test configuration**: `nginx -t` to check configuration file syntax
- **Missing semicolons**: Every directive must end with a semicolon
- **Unmatched braces**: Check that `{}` are properly paired
- **include paths**: Ensure included files exist and paths are correct

### Static Files Return 404
- **Check root path**: Confirm the root directive points to the correct directory
- **alias vs root**: `alias` replaces the location path, `root` appends to it
- **try_files**: Ensure `try_files $uri $uri/ /index.html` is configured correctly (required for SPA applications)
- **Case sensitivity**: Linux file systems are case-sensitive

---

## systemd Issues

### Service Fails to Start
- **View logs**: `journalctl -u <servicename> -n 50 --no-pager`
- **Check ExecStart**: Ensure the command path is absolutely correct; use absolute paths
- **Check user permissions**: Verify the user specified in `User=` has execution permissions
- **Check dependencies**: `After=` and `Requires=` ensure dependency services have started

### Service Restart Loop
- **Check RestartSec**: Set a reasonable restart interval, e.g., `RestartSec=5`
- **Memory leak**: `journalctl -u <service>` to check for OOM-related log entries
- **Dependency services**: Check if dependency services like databases are functioning normally
- **StartLimitIntervalSec**: Configure restart count limits to prevent infinite restarts

### Environment Variables Not Loaded
- **Check EnvironmentFile**: Confirm the path is correct; file format must be `KEY=VALUE` (no export)
- **Check .env format**: `export KEY=VALUE` is not supported; variable expansion is not supported
- **Override order**: Command line > Environment > EnvironmentFile
- **Reload**: After modifying the service file, run `systemctl daemon-reload`

---

## SSL Issues

### Certificate Acquisition Failure
- **Check DNS**: `dig <domain>` to confirm the domain resolves to the server IP
- **Check port 80**: Let's Encrypt requires HTTP-01 validation; ensure port 80 is accessible
- **Check firewall**: `ufw status` or `firewall-cmd --list-all`
- **Rate limiting**: Let's Encrypt has rate limits; do not request certificates too frequently

### Certificate Renewal Failure
- **View logs**: `cat /var/log/letsencrypt/letsencrypt.log`
- **Check disk space**: `df -h` to ensure sufficient space is available
- **Check network**: Renewal requires access to external validation servers
- **Test renewal**: `certbot renew --dry-run` to simulate renewal

### Mixed Content
- **Investigate pages**: Browser DevTools > Console > Mixed Content warnings
- **Global replacement**: Replace `http://` with `https://` in the database
- **CSP header**: Add `Content-Security-Policy: upgrade-insecure-requests`
- **Nginx configuration**: Add `add_header Content-Security-Policy "upgrade-insecure-requests"`

### Incomplete Certificate Chain
- **Check certificate**: `openssl s_client -connect <domain>:443 -servername <domain>`
- **Missing intermediate certificate**: Use fullchain.pem instead of cert.pem
- **Testing tool**: [SSL Labs](https://www.ssllabs.com/ssltest/) for online detection

---

## General Issues

### Port Already in Use
- **View usage**: `ss -tlnp | grep :<port>` or `lsof -i :<port>`
- **Kill process**: `kill <PID>` or `kill -9 <PID>` (force)
- **Change port**: Modify the application configuration to use a different port

### Insufficient Memory
- **View memory**: `free -h` to check available memory
- **Add Swap**: `fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile`
- **Optimize application**: Check for memory leaks, add caching strategies, limit worker count

### DNS Not Yet Effective
- **View resolution**: `dig <domain>` or `nslookup <domain>`
- **Wait for propagation**: DNS propagation can take up to 48 hours
- **Check NS records**: Confirm the domain uses the correct name servers
- **Local cache**: `systemd-resolve --flush-caches` or restart nscd

### Insufficient Permissions
- **View permissions**: `sudo -l` to check available sudo privileges for the current user
- **Docker group**: `usermod -aG docker $USER` requires re-login to take effect
- **File ownership**: `chown -R user:user /path` to change file ownership
- **Directory permissions**: Directories require `x` (execute) permission to be entered
