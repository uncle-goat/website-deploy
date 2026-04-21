# 更新部署指南

## 概述

### 首次部署 vs 更新部署

| 维度 | 首次部署 | 更新部署 |
|------|---------|---------|
| 定义 | 从零搭建完整运行环境 | 代码变更后重建并重启服务 |
| 环境检测 | 需要检测 OS、语言版本、包管理器 | 跳过，环境已就绪 |
| 依赖安装 | 全量安装 | 仅安装新增/变更的依赖 |
| 配置生成 | 生成 `.env`、`nginx.conf`、`docker-compose.yml` 等 | 仅检查是否有新配置项 |
| 数据库 | 初始化建库建表 | 执行增量迁移（如有） |
| 风险 | 低（新环境无历史包袱） | 高（必须保证线上服务不中断） |

**核心原则**：更新部署的目标是在不中断现有服务的前提下，将代码变更安全地发布到生产环境。AI 在执行更新部署时，**必须严格按照以下四个阶段顺序执行**，不得跳过任何步骤。

---

## 更新部署完整流程（AI 必须严格按此顺序执行）

### Phase 1: 部署前检查

> **AI 注意**：此阶段所有检查必须全部通过后，才能进入 Phase 2。任何一项检查失败，必须先解决问题再继续。

#### 1.1 备份当前版本

**为什么**：万一更新失败，可以立即回滚到上一个正常运行的版本，将故障时间压缩到最小。

**Docker 部署备份**：

```bash
# 记录当前运行的镜像信息
docker compose ps --format "table {{.Name}}\t{{.Image}}\t{{.Status}}" > /backups/pre-deploy-$(date +%Y%m%d%H%M%S).txt

# 保存当前应用镜像（仅保存 app 服务镜像，不保存数据库镜像）
docker save $(docker compose images -q app) -o /backups/app-image-$(date +%Y%m%d%H%M%S).tar
```

**服务器部署备份**：

```bash
# 打包当前代码（排除不必要的目录以节省空间和时间）
cd /var/www/myapp
tar -czf /backups/myapp-backup-$(date +%Y%m%d%H%M%S).tar.gz \
  --exclude='node_modules' \
  --exclude='.git' \
  --exclude='venv' \
  --exclude='__pycache__' \
  --exclude='.next' \
  --exclude='dist' \
  --exclude='*.log' \
  .
```

**数据库备份（仅当此次更新涉及数据库 schema 变更时执行）**：

```bash
# MySQL
mysqldump -u root -p"$DB_PASSWORD" "$DB_NAME" > /backups/db-backup-$(date +%Y%m%d%H%M%S).sql

# PostgreSQL
pg_dump -U "$DB_USER" -d "$DB_NAME" -F c -f /backups/db-backup-$(date +%Y%m%d%H%M%S).dump

# MongoDB
mongodump --uri="$MONGO_URI" --out=/backups/mongo-backup-$(date +%Y%m%d%H%M%S)
```

**自动清理旧备份（保留最近 3 个）**：

```bash
# 清理代码备份
ls -t /backups/myapp-backup-*.tar.gz | tail -n +4 | xargs -r rm -f

# 清理镜像备份
ls -t /backups/app-image-*.tar | tail -n +4 | xargs -r rm -f

# 清理数据库备份
ls -t /backups/db-backup-* | tail -n +4 | xargs -r rm -f
```

#### 1.2 检查变更内容

**目的**：确认哪些文件发生了变化，判断是否涉及数据库迁移、配置变更等高风险操作。

```bash
# 查看最近一次提交的变更概览
git log --oneline -5
git diff --stat HEAD~1

# 如果是多次提交，查看所有未部署的变更
git diff --stat origin/main...HEAD  # 如果在本地分支
git diff --stat HEAD~3..HEAD        # 查看最近 3 次提交

# 检查是否包含数据库迁移文件
git diff --name-only HEAD~1 | grep -E '(migration|migrate|schema)' && echo "WARNING: 数据库迁移文件已变更！" || echo "无数据库迁移变更"

# 检查是否包含配置文件变更
git diff --name-only HEAD~1 | grep -E '(\.env\.example|docker-compose|nginx\.conf|Dockerfile)' && echo "WARNING: 配置文件已变更！" || echo "无配置文件变更"
```

**变更分类与处理策略**：

| 变更类型 | 风险等级 | 额外操作 |
|---------|---------|---------|
| 纯前端代码（HTML/CSS/JS/图片） | 低 | 正常流程 |
| 后端业务逻辑 | 中 | 部署后重点检查相关 API |
| 数据库 migration 文件 | 高 | 必须备份数据库，部署后执行迁移 |
| 环境变量 / 配置文件 | 高 | 必须对比 `.env.example`，确认新变量 |
| 依赖版本变更（package.json / requirements.txt） | 中 | 需要重新安装依赖 |
| Dockerfile 变更 | 中 | 需要重新构建镜像 |

#### 1.3 预检环境

**目的**：确认部署环境仍然正常，避免在异常环境中叠加更新导致问题难以排查。

```bash
# 检查磁盘空间（至少需要 2GB 可用）
AVAILABLE=$(df / | awk 'NR==2 {print $4}')
if [ "$AVAILABLE" -lt 2097152 ]; then
  echo "ERROR: 磁盘空间不足，可用空间: $((AVAILABLE/1024))MB，需要至少 2048MB"
  exit 1
fi
echo "磁盘空间充足: $((AVAILABLE/1024/1024))GB 可用"

# Docker 部署：检查 Docker daemon 是否运行
docker info > /dev/null 2>&1 && echo "Docker 运行正常" || echo "ERROR: Docker daemon 未运行"

# 检查服务当前是否健康
curl -sf http://localhost:${PORT}/health && echo "服务健康检查通过" || echo "WARNING: 服务健康检查失败，当前服务可能已异常"
```

---

### Phase 2: 执行更新

> **AI 注意**：根据实际部署方式，选择以下三条路径之一执行。不得混用不同路径的命令。

#### 2.1 Docker 部署路径

```bash
# Step 1: 拉取最新代码
git fetch origin
git pull origin main

# Step 2: 检查 .env 文件是否有新变量
diff <(grep -v '^#' .env | grep -v '^$' | sort) \
     <(grep -v '^#' .env.example | grep -v '^$' | sort) \
  && echo ".env 无新变量" \
  || echo "WARNING: .env 与 .env.example 存在差异，请检查是否需要添加新变量"

# Step 3: 重建镜像（仅重建应用镜像，不重建数据库等基础服务）
docker compose build --no-cache app

# Step 4: 滚动更新（仅更新 app 服务，数据库和缓存等不受影响）
docker compose up -d --build app

# Step 5: 等待健康检查通过（最多等待 120 秒）
echo "等待服务启动..."
for i in $(seq 1 24); do
  STATUS=$(docker compose ps --format "{{.Health}}" app 2>/dev/null || echo "unknown")
  if [ "$STATUS" = "healthy" ]; then
    echo "服务已健康启动"
    break
  fi
  if [ "$i" -eq 24 ]; then
    echo "ERROR: 服务启动超时（120秒），请检查日志"
    docker compose logs --tail=50 app
    exit 1
  fi
  sleep 5
done

# Step 6: 如果有数据库迁移，在服务健康后执行
if git diff --name-only HEAD~1 | grep -qE '(migration|migrate)'; then
  echo "检测到数据库迁移文件，正在执行迁移..."
  docker compose exec -T app npx prisma migrate deploy
  # 或: docker compose exec -T app python manage.py migrate --noinput
  # 或: docker compose exec -T app npx typeorm migration:run
  echo "数据库迁移完成"
fi

# Step 7: 清理旧镜像
docker image prune -f
```

#### 2.2 服务器部署路径（Nginx + systemd）

```bash
# Step 1: 拉取最新代码
git fetch origin
git pull origin main

# Step 2: 安装新依赖（仅安装生产依赖）
# Node.js 项目
npm ci --production
# Python 项目
# pip install -r requirements.txt --no-cache-dir

# Step 3: 执行构建
npm run build
# 构建产物通常输出到 dist/ 或 build/ 目录

# Step 4: 如果有数据库迁移
if git diff --name-only HEAD~1 | grep -qE '(migration|migrate)'; then
  echo "检测到数据库迁移文件，正在执行迁移..."
  python manage.py migrate --noinput
  # 或: npx prisma migrate deploy
  echo "数据库迁移完成"
fi

# Step 5: 重启服务
sudo systemctl restart myapp

# Step 6: 等待服务就绪并检查状态
sleep 3
sudo systemctl status myapp --no-pager
if [ $? -ne 0 ]; then
  echo "ERROR: 服务启动失败，正在查看错误日志..."
  sudo journalctl -u myapp --since "1 min ago" --no-pager
  exit 1
fi

# Step 7: Nginx 无需重启（反向代理配置未变，仅后端服务重启）
# 如果此次更新涉及 Nginx 配置变更，才需要:
# sudo nginx -t && sudo systemctl reload nginx
```

#### 2.3 远程服务器部署（SSH）

```bash
# Step 1: 本地同步文件到远程服务器
# 排除不需要上传的目录和文件
rsync -avz --delete \
  --exclude='node_modules' \
  --exclude='.git' \
  --exclude='.env' \
  --exclude='venv' \
  --exclude='__pycache__' \
  --exclude='.next' \
  --exclude='dist' \
  --exclude='*.log' \
  ./ user@server:/var/www/myapp/

# Step 2: SSH 远程执行更新命令（组合为一条命令，确保原子性）
ssh user@server bash -c "'cd /var/www/myapp && \
  npm ci --production && \
  npm run build && \
  sudo systemctl restart myapp && \
  sleep 3 && \
  sudo systemctl status myapp --no-pager'"

# Step 3: 远程健康检查
ssh user@server "curl -sf http://localhost:${PORT}/health" \
  && echo "远程服务健康检查通过" \
  || echo "ERROR: 远程服务健康检查失败"
```

---

### Phase 3: 部署后验证

> **AI 注意**：此阶段所有验证项必须全部通过，部署才算成功。任何一项失败，必须立即排查或执行回滚。

#### 3.1 健康检查

```bash
# 基础健康检查
curl -sf -o /dev/null -w "HTTP Status: %{http_code}\n" https://your-domain.com/health
# 期望输出: HTTP Status: 200

# 带超时的健康检查（最多等待 30 秒）
timeout 30 bash -c 'until curl -sf https://your-domain.com/health > /dev/null 2>&1; do sleep 2; done' \
  && echo "健康检查通过" \
  || echo "ERROR: 健康检查超时"
```

#### 3.2 检查应用日志

```bash
# Docker 部署
docker compose logs --tail=50 app
docker compose logs --tail=50 app 2>&1 | grep -iE '(error|exception|fatal|panic)' && echo "WARNING: 发现错误日志" || echo "无错误日志"

# systemd 服务
sudo journalctl -u myapp --since "2 min ago" --no-pager
sudo journalctl -u myapp --since "2 min ago" --no-pager | grep -iE '(error|exception|fatal|panic)' && echo "WARNING: 发现错误日志" || echo "无错误日志"

# Nginx 错误日志
sudo tail -20 /var/log/nginx/error.log
```

#### 3.3 功能验证

根据项目类型，验证以下关键功能：

- **首页加载**：`curl -sf -o /dev/null -w "%{http_code}" https://your-domain.com/` 应返回 200
- **API 接口**：测试核心 API 端点是否正常响应
- **静态资源**：确认 CSS/JS/图片等静态资源可正常加载
- **数据库读写**：如果涉及数据库变更，验证增删改查操作正常

---

### Phase 4: 清理

```bash
# Docker 清理
docker image prune -f          # 删除 dangling 镜像（未被任何容器引用的镜像）
docker builder prune -f         # 清理构建缓存

# 服务器清理
# 删除旧的备份文件（保留最近 3 个）
ls -t /backups/myapp-backup-*.tar.gz | tail -n +4 | xargs -r rm -f
ls -t /backups/app-image-*.tar | tail -n +4 | xargs -r rm -f
ls -t /backups/db-backup-* | tail -n +4 | xargs -r rm -f

# 清理构建临时文件
rm -rf /tmp/build-* /tmp/npm-* /tmp/pip-*

# 日志清理（限制日志大小为 100MB）
sudo journalctl --vacuum-size=100M

# 最终磁盘检查
df -h /
echo "部署后磁盘空间确认完毕"
```

---

## 回滚机制

> **AI 注意**：当 Phase 3 验证失败时，**必须立即执行回滚**，不得尝试在故障状态下修复。修复应在回滚恢复服务后，在开发环境中进行。

### 触发条件

满足以下任一条件，立即触发回滚：

1. 健康检查连续 3 次失败
2. 服务启动后日志中出现持续报错（非偶发错误）
3. 关键功能不可用（首页无法访问、核心 API 返回 500）
4. 响应时间异常升高（超过正常值 3 倍）

### Docker 回滚

```bash
# Step 1: 标记当前（坏的）版本
docker tag myapp:latest myapp:failed-$(date +%Y%m%d%H%M%S)

# Step 2: 停止当前容器
docker compose down app

# Step 3: 恢复备份镜像
docker load -i /backups/app-image-YYYYMMDDHHMMSS.tar

# Step 4: 使用备份镜像重新启动
docker compose up -d app

# Step 5: 验证回滚是否成功
sleep 5
docker compose ps
curl -sf http://localhost:${PORT}/health && echo "回滚成功" || echo "回滚失败，需要人工介入"
```

### 服务器回滚

```bash
# Step 1: 停止当前服务
sudo systemctl stop myapp

# Step 2: 恢复代码备份（找到最近的备份文件）
BACKUP_FILE=$(ls -t /backups/myapp-backup-*.tar.gz | head -1)
echo "使用备份文件: $BACKUP_FILE"

# Step 3: 清理当前代码并恢复
cd /var/www/myapp
rm -rf $(ls -A | grep -v '^\.env$')  # 保留 .env 文件
tar -xzf "$BACKUP_FILE"

# Step 4: 重新安装依赖和构建
npm ci --production
npm run build

# Step 5: 启动服务
sudo systemctl start myapp
sleep 3
sudo systemctl status myapp --no-pager

# Step 6: 验证回滚
curl -sf http://localhost:${PORT}/health && echo "回滚成功" || echo "回滚失败，需要人工介入"
```

### 数据库回滚

```bash
# Django 回滚到指定迁移
python manage.py migrate app_name migration_name

# Prisma 回滚
npx prisma migrate resolve --rolled-back migration_name

# 如果有数据库备份，直接恢复（最彻底但数据会丢失回滚期间的变更）
# MySQL
mysql -u root -p"$DB_PASSWORD" "$DB_NAME" < /backups/db-backup-YYYYMMDDHHMMSS.sql

# PostgreSQL
pg_restore -U "$DB_USER" -d "$DB_NAME" -c /backups/db-backup-YYYYMMDDHHMMSS.dump

# MongoDB
mongorestore --uri="$MONGO_URI" --drop /backups/mongo-backup-YYYYMMDDHHMMSS
```

---

## 零停机部署策略

### Docker 滚动更新

`docker compose up -d --build` 默认行为即为滚动更新：先启动新容器，新容器通过健康检查后再停止旧容器。无需额外配置即可实现零停机。

如需多实例滚动更新：

```yaml
# docker-compose.yml
services:
  app:
    image: myapp:latest
    deploy:
      replicas: 2
      update_config:
        parallelism: 1      # 每次更新 1 个实例
        delay: 10s          # 实例间间隔 10 秒
        order: start-first  # 先启动新的再停止旧的
      restart_policy:
        condition: on-failure
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:3000/health"]
      interval: 5s
      timeout: 3s
      retries: 3
```

### 蓝绿部署（高级）

适用于对可用性要求极高的场景：

```
                    ┌──────────────┐
                    │   Nginx /    │
    用户请求 ──────►│   负载均衡器  │──────┐
                    └──────────────┘      │
                               ┌─────────┴─────────┐
                               ▼                   ▼
                        ┌─────────────┐     ┌─────────────┐
                        │  蓝环境      │     │  绿环境      │
                        │  (当前版本)  │     │  (新版本)    │
                        │  v1.2.0     │     │  v1.3.0     │
                        └─────────────┘     └─────────────┘
```

**操作流程**：

1. 当前流量全部指向蓝环境（生产环境）
2. 在绿环境部署新版本代码
3. 在绿环境执行数据库迁移（如果需要）
4. 验证绿环境健康检查通过
5. 修改 Nginx upstream 或 DNS，将流量切换到绿环境
6. 观察绿环境运行状况（至少 5 分钟）
7. 如果出问题，立即切回蓝环境（仅需改回 upstream 配置并 reload Nginx）

```bash
# Nginx 切换示例
# 切换到绿环境
sudo sed -i 's/upstream blue/upstream green/' /etc/nginx/conf.d/upstream.conf
sudo nginx -t && sudo systemctl reload nginx

# 切回蓝环境
sudo sed -i 's/upstream green/upstream blue/' /etc/nginx/conf.d/upstream.conf
sudo nginx -t && sudo systemctl reload nginx
```

### PM2 零停机

```bash
# 优雅重启：等待现有请求处理完毕后再重启
pm2 reload app

# 与 pm2 restart 的区别：
# pm2 restart  → 直接杀进程，正在处理的请求会丢失
# pm2 reload   → 先 fork 新进程，新进程就绪后再终止旧进程

# 确认重载成功
pm2 status
pm2 logs app --lines 20 --nostream
```

---

## CI/CD 自动触发

### GitHub Actions 示例

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to server
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.HOST }}
          username: ${{ secrets.USERNAME }}
          key: ${{ secrets.SSH_KEY }}
          script: |
            cd /var/www/myapp
            git pull origin main
            npm ci --production
            npm run build
            sudo systemctl restart myapp
            sleep 3
            curl -sf http://localhost:3000/health || exit 1
```

### Webhook 触发

在服务器上部署一个监听脚本，代码仓库 push 事件触发自动部署：

```bash
# /opt/deploy/webhook-listener.sh
#!/bin/bash
while true; do
  # 监听 webhook 端口（需配合 webhook 服务如 webhookd）
  # 收到 push 事件后执行部署脚本
  /opt/deploy/deploy.sh >> /var/log/deploy.log 2>&1
done
```

### 定时部署（不推荐）

```bash
# cron 定时拉取（仅作为最后手段，强烈建议使用 CI/CD）
# */30 * * * * cd /var/www/myapp && git pull origin main && npm run build && sudo systemctl restart myapp
```

> **警告**：定时部署无法保证代码质量（未经测试的代码也会被部署），且无法追溯部署历史。仅在无法搭建 CI/CD 的极端情况下使用。

---

## AI 操作检查清单

每次执行更新部署时，AI 必须逐项确认以下清单：

- [ ] Phase 1.1 - 已备份当前版本（代码 + 镜像 + 数据库如需要）
- [ ] Phase 1.2 - 已检查变更内容（确认是否有迁移/配置变更）
- [ ] Phase 1.3 - 已预检环境（磁盘空间、Docker、服务健康）
- [ ] Phase 2 - 已选择正确的部署路径并按步骤执行
- [ ] Phase 3.1 - 健康检查通过
- [ ] Phase 3.2 - 应用日志无异常错误
- [ ] Phase 3.3 - 关键功能验证通过
- [ ] Phase 4 - 已清理旧备份和临时文件
- [ ] 如验证失败 - 已执行回滚并恢复服务
