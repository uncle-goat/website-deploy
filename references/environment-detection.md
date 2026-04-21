# 环境检测指南

本文档说明 `detect-environment.sh` 的输出字段及其在部署决策中的用途。

## 检测项说明

### os — 操作系统信息

| 字段 | 说明 |
|------|------|
| name | 发行版名称（Ubuntu / CentOS / Debian / Alpine 等） |
| version | 主版本号 |
| arch | 架构（x86_64 / aarch64） |

**决策影响：** 不同发行版使用不同的包管理器（apt / yum / apk），影响依赖安装命令的生成。arch 决定能否拉取对应架构的 Docker 镜像。

### resources — 硬件资源

| 字段 | 说明 |
|------|------|
| cpu_cores | CPU 核心数 |
| memory_mb | 可用内存（MB） |
| disk_free_gb | 磁盘剩余空间（GB） |

**最低资源要求：**

| 部署方式 | 最低内存 | 最低磁盘 |
|----------|----------|----------|
| Docker 部署 | 2 GB | 10 GB |
| 完整服务端部署 | 1 GB | 5 GB |
| 静态站点 | 512 MB | 1 GB |
| CMS（WordPress） | 2 GB | 20 GB |

资源不足时应提示用户并给出扩容建议，而非强行部署。

### docker — Docker 环境

| 字段 | 说明 |
|------|------|
| installed | 是否已安装 |
| version | Docker Engine 版本 |
| compose_version | Docker Compose 版本 |
| daemon_running | 守护进程是否运行中 |

**版本要求：** Docker Engine >= 20.10，Compose >= 2.0。版本过低时提示升级。

### nginx — Nginx

| 字段 | 说明 |
|------|------|
| installed | 是否已安装 |
| version | Nginx 版本 |

Nginx 可用时优先复用，避免重复安装。用于反向代理和静态文件服务。

### 运行时环境

检测以下运行时是否安装及版本：`nodejs`、`python`、`php`、`go`、`java`。

**常见框架版本要求速查：**

| 框架 | 运行时 | 最低版本 |
|------|--------|----------|
| Next.js / Nuxt | Node.js | 18.x |
| Django / Flask | Python | 3.9 |
| WordPress / Laravel | PHP | 8.1 |
| Hugo | Go | 1.20 |
| Spring Boot | Java | 17 |

### ports_in_use — 已占用端口

列出当前被监听的端口。部署前必须检查目标端口（默认 80/443）是否冲突，冲突时需终止占用进程或更换端口。

### ssh — SSH 配置

| 字段 | 说明 |
|------|------|
| configured | 是否已配置 |
| key_files | 可用密钥文件列表 |

远程部署场景下使用。有密钥文件时可直接调用 `deploy-ssh.sh`。

### firewall — 防火墙状态

| 字段 | 说明 |
|------|------|
| type | 防火墙类型（ufw / iptables / firewalld） |
| status | 是否启用 |
| open_ports | 已放行端口列表 |

Web 服务需要 80（HTTP）和 443（HTTPS）端口可达。防火墙启用但未放行时，应提示用户开放。

### is_container — 是否运行在容器内

布尔值。容器内通常无法使用 `systemd`，影响服务管理方式的选择（用 `supervisord` 或直接前台运行替代）。

### current_user / has_sudo — 权限上下文

| 字段 | 说明 |
|------|------|
| current_user | 当前用户名 |
| has_sudo | 是否有 sudo 权限 |

无 sudo 权限时无法安装系统包或绑定 80/443 端口，应提前告知用户。

---

## 环境类型判断逻辑

根据检测结果自动分类环境，决定部署策略：

```
if ssh.configured AND target_is_remote:
    → Remote SSH（使用 deploy-ssh.sh 远程部署）

elif docker.installed AND docker.daemon_running:
    → Docker-ready（优先使用 Docker / Compose 部署）

elif any([nginx, nodejs, python, php, go, java]) installed:
    → Bare-metal with tools（已有工具，直接安装依赖并部署）

else:
    → Fresh server（需完整安装，先装运行时再部署）
```

**优先级：** 远程 SSH > Docker > 已有工具 > 全新安装。

---

## 常见问题

### Docker 已安装但守护进程未运行

```bash
sudo systemctl start docker
sudo systemctl enable docker   # 开机自启
```

### 权限不足（Permission denied）

```bash
# 将用户加入 docker 组，免 sudo 使用 docker
sudo usermod -aG docker $USER
newgrp docker
```

### 端口被占用

```bash
# 查看占用进程
sudo lsof -i :80
# 终止进程或更换部署端口
```

### 磁盘空间不足

```bash
docker system prune -a   # 清理无用镜像和容器
sudo apt autoremove -y   # 清理系统包缓存
```

### 内存不足

```bash
# 创建 2GB swap 文件
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
# 持久化：在 /etc/fstab 末尾追加
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```
