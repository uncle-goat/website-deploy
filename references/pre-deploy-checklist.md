# 部署前检查清单

## 环境检查

- [ ] 操作系统版本兼容（Ubuntu 20.04+ / Debian 11+ / CentOS 8+）
- [ ] 磁盘空间充足（Docker 部署: 10GB+，服务器部署: 5GB+，CMS 系统: 20GB+）
- [ ] 内存充足（Docker 部署: 2GB+，服务器部署: 1GB+，CMS 系统: 2GB+）
- [ ] 所需端口未被占用（80, 443, 3000, 3306, 5432, 6379, 8080 等）
- [ ] 防火墙已开放必要端口（80, 443）
- [ ] 当前用户有 sudo 权限（如需安装软件包）

## 项目检查

- [ ] 构建命令在本地执行成功（`npm run build` / `python setup.py` 等）
- [ ] 所有环境变量已准备（`.env` 文件或 `.env.example` 模板）
- [ ] 敏感信息未硬编码在代码中（API keys、passwords、tokens）
- [ ] `.gitignore` 包含 `.env`、`node_modules`、`__pycache__`、`.venv` 等
- [ ] 数据库迁移脚本已准备并测试
- [ ] 依赖版本已锁定（`package-lock.json`、`pnpm-lock.yaml`、`requirements.txt`）
- [ ] 代码中无调试代码（`console.log`、`debugger`、`print` 调试语句）
- [ ] 生产环境配置与开发环境已分离

## 网络检查

- [ ] 域名 DNS 已解析到服务器 IP（如使用域名）
- [ ] SSL 证书可获取（端口 80 可访问，DNS 已生效）
- [ ] 服务器可通过 SSH 访问（远程部署时）
- [ ] 服务器安全组/防火墙规则已配置

## Docker 特定检查

- [ ] Docker Engine 20.10+ 已安装
- [ ] Docker Compose 2.0+ 已安装
- [ ] Docker daemon 正在运行（`systemctl status docker`）
- [ ] `.dockerignore` 文件已创建（排除 `.git`、`node_modules`、`.env` 等）
- [ ] Docker 镜像构建在本地测试通过
- [ ] 容器间网络通信配置正确

## 服务器特定检查

- [ ] Nginx 已安装或可安装（`nginx -v`）
- [ ] Node.js / Python / PHP 版本与项目要求匹配
- [ ] systemd 可用（非容器环境）
- [ ] 日志目录已创建且有写入权限
- [ ] 应用运行用户已创建（非 root 用户运行应用）
