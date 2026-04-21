# 常见问题排查指南

## Docker 问题

### 构建失败
- **检查 Dockerfile 语法**：确保 FROM、RUN、COPY 等指令拼写正确，注意大小写
- **检查 .dockerignore**：排除不必要的文件（.git、node_modules），减少构建上下文大小
- **检查网络**：构建时需要拉取基础镜像和依赖，确保网络通畅
- **检查基础镜像**：确认基础镜像标签存在，如 `node:20-alpine` 而非 `node:latest`（latest 可能被替换）
- **多阶段构建**：大型项目建议使用多阶段构建减小最终镜像体积

### 容器启动后立即退出
- **查看日志**：`docker compose logs <service>` 或 `docker logs <container>`
- **检查 CMD/ENTRYPOINT**：确保前台运行，不要使用 `npm start` 后台模式
- **检查环境变量**：缺少必要的环境变量可能导致程序崩溃
- **检查文件权限**：挂载的文件/目录权限是否正确
- **检查依赖**：数据库等依赖服务是否已就绪

### 网络不通
- **检查网络配置**：`docker network ls` 和 `docker network inspect <network>`
- **检查服务名称**：容器间通信使用服务名而非 IP（如 `http://db:5432`）
- **检查防火墙**：宿主机防火墙可能阻止容器端口映射
- **使用 host 网络**：调试时可用 `network_mode: host` 排除网络问题

### 卷挂载问题
- **检查路径**：确保宿主机路径存在且正确，注意相对路径与绝对路径
- **检查权限**：容器内用户（通常 root）与宿主机文件权限是否匹配
- **SELinux**（CentOS）：添加 `:z` 或 `:Z` 后缀，如 `-v /data:/app:z`
- **命名卷 vs 绑定挂载**：生产环境推荐命名卷，开发环境可用绑定挂载

### 磁盘空间不足
- **清理无用资源**：`docker system prune -a`（删除所有未使用的镜像、容器、网络）
- **清理卷**：`docker volume prune`（删除未使用的卷，注意备份数据）
- **查看占用**：`docker system df` 查看各部分占用空间
- **日志限制**：在 compose 文件中配置日志驱动和大小限制

---

## Nginx 问题

### 502 Bad Gateway
- **上游服务未运行**：检查后端服务状态，`systemctl status <service>`
- **端口错误**：确认 proxy_pass 中的端口号与后端服务一致
- **Socket 权限**：使用 Unix socket 时，确保 Nginx 用户有读写权限
- **超时**：增加 `proxy_read_timeout` 和 `proxy_connect_timeout`

### 503 Service Unavailable
- **上游过载**：后端服务处理能力不足，增加 worker 数或使用负载均衡
- **服务未就绪**：检查后端启动时间，配置健康检查
- **限流触发**：检查 `limit_req` 配置是否过于严格

### 403 Forbidden
- **文件权限**：确保 Nginx 用户（www-data/nginx）对文件有读取权限
- **目录索引**：缺少 index 文件且未开启 `autoindex on`
- **SELinux**：`setenforce 0` 临时关闭测试，或配置正确的 SELinux 上下文
- **deny 规则**：检查是否有 `deny all` 或其他访问控制规则

### 配置语法错误
- **测试配置**：`nginx -t` 检查配置文件语法
- **缺少分号**：每条指令必须以分号结尾
- **括号不匹配**：检查 `{}` 是否成对
- **include 路径**：确保 include 的文件存在且路径正确

### 静态文件 404
- **检查 root 路径**：确认 root 指令指向正确的目录
- **alias vs root**：`alias` 会替换 location 路径，`root` 会拼接路径
- **try_files**：确保 `try_files $uri $uri/ /index.html` 配置正确（SPA 应用必需）
- **大小写敏感**：Linux 文件系统区分大小写

---

## systemd 问题

### 服务启动失败
- **查看日志**：`journalctl -u <servicename> -n 50 --no-pager`
- **检查 ExecStart**：确保命令路径绝对正确，使用绝对路径
- **检查用户权限**：`User=` 指定的用户是否有执行权限
- **检查依赖**：`After=` 和 `Requires=` 确保依赖服务已启动

### 服务重启循环
- **检查 RestartSec**：设置合理的重启间隔，如 `RestartSec=5`
- **内存泄漏**：`journalctl -u <service>` 查看是否有 OOM 相关日志
- **依赖服务**：检查数据库等依赖服务是否正常
- **StartLimitIntervalSec**：配置重启次数限制，避免无限重启

### 环境变量未加载
- **检查 EnvironmentFile**：确认路径正确，文件格式为 `KEY=VALUE`（无 export）
- **检查 .env 格式**：不支持 `export KEY=VALUE`，不支持变量展开
- **覆盖顺序**：命令行 > Environment > EnvironmentFile
- **重新加载**：修改 service 文件后需 `systemctl daemon-reload`

---

## SSL 问题

### 证书获取失败
- **检查 DNS**：`dig <domain>` 确认域名解析到服务器 IP
- **检查端口 80**：Let's Encrypt 需要通过 HTTP-01 验证，确保 80 端口可访问
- **检查防火墙**：`ufw status` 或 `firewall-cmd --list-all`
- **频率限制**：Let's Encrypt 有速率限制，不要频繁申请

### 证书续期失败
- **查看日志**：`cat /var/log/letsencrypt/letsencrypt.log`
- **检查磁盘空间**：`df -h` 确保有足够空间
- **检查网络**：续期需要访问外部验证服务器
- **测试续期**：`certbot renew --dry-run` 模拟续期

### 混合内容
- **排查页面**：浏览器开发者工具 → Console → Mixed Content 警告
- **全局替换**：数据库中 `http://` 替换为 `https://`
- **CSP 头**：添加 `Content-Security-Policy: upgrade-insecure-requests`
- **Nginx 配置**：添加 `add_header Content-Security-Policy "upgrade-insecure-requests"`

### 证书链不完整
- **检查证书**：`openssl s_client -connect <domain>:443 -servername <domain>`
- **缺少中间证书**：使用 fullchain.pem 而非 cert.pem
- **测试工具**：[SSL Labs](https://www.ssllabs.com/ssltest/) 在线检测

---

## 通用问题

### 端口被占用
- **查看占用**：`ss -tlnp | grep :<port>` 或 `lsof -i :<port>`
- **终止进程**：`kill <PID>` 或 `kill -9 <PID>`（强制）
- **更换端口**：修改应用配置使用其他端口

### 内存不足
- **查看内存**：`free -h` 查看可用内存
- **添加 Swap**：`fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile`
- **优化应用**：检查内存泄漏，增加缓存策略，限制 worker 数量

### DNS 未生效
- **查看解析**：`dig <domain>` 或 `nslookup <domain>`
- **等待传播**：DNS 传播最长需要 48 小时
- **检查 NS 记录**：确认域名使用了正确的域名服务器
- **本地缓存**：`systemd-resolve --flush-caches` 或重启 nscd

### 权限不足
- **查看权限**：`sudo -l` 查看当前用户可用的 sudo 权限
- **Docker 组**：`usermod -aG docker $USER` 后需重新登录
- **文件所有者**：`chown -R user:user /path` 修改文件归属
- **目录权限**：目录需要 `x`（执行）权限才能进入
