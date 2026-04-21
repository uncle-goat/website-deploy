# Docker 容器化部署指南

## 为什么选择 Docker

Docker 通过容器化技术解决了传统部署中的诸多痛点：

- **环境一致性**：开发、测试、生产环境完全一致，彻底消除"在我机器上能跑"的问题。镜像打包了应用及其全部依赖，任何地方运行结果相同。
- **隔离性**：每个容器拥有独立的文件系统、网络栈和进程空间，应用之间互不干扰，可以安全地在同一台主机上运行不同版本的运行时。
- **易于扩展**：结合 Docker Compose 或 Kubernetes，可以快速水平扩展服务实例，应对流量高峰。
- **可复现构建**：Dockerfile 即构建文档，任何人在任何时间都能从同一份 Dockerfile 构建出完全相同的镜像。
- **干净销毁**：`docker compose down` 一条命令即可移除所有容器和网络，不留残留，非常适合临时环境和 CI/CD 场景。

## Dockerfile 最佳实践

### 多阶段构建

多阶段构建的核心思想：最终镜像只包含运行时所需文件，将构建工具、源码等排除在外。一个典型的 Node.js 项目，未优化镜像可能 500MB+，多阶段构建后通常只有 50-100MB。

```dockerfile
# 阶段一：构建
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# 阶段二：运行
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

# 仅复制生产依赖和构建产物
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public

EXPOSE 3000
USER node
CMD ["node", "dist/server.js"]
```

Python 项目同理：

```dockerfile
# 阶段一：构建
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 阶段二：运行
FROM python:3.12-slim AS runner
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY . .
EXPOSE 8000
CMD ["gunicorn", "app:app", "-b", "0.0.0.0:8000"]
```

### 非 root 用户

默认情况下容器以 root 运行。如果容器被攻破，攻击者将获得宿主机 root 权限。创建专用用户是最基本的安全加固措施。

```dockerfile
# 创建用户和组
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# 设置工作目录并移交所有权
WORKDIR /app
COPY --chown=appuser:appgroup . .

# 切换到非 root 用户
USER appuser

EXPOSE 3000
CMD ["node", "dist/server.js"]
```

如果应用需要监听 80 端口，不要用 root 运行，而是将容器内端口映射到宿主机 80 端口：`docker run -p 80:3000 ...`。

### .dockerignore

`.dockerignore` 防止不必要的文件进入构建上下文，加速构建并减小镜像体积：

```
node_modules
.git
.gitignore
.env
.env.*
__pycache__
*.pyc
.venv
venv
dist
.next
coverage
.vscode
.idea
*.md
*.log
.DS_Store
```

对于多阶段构建，`dist` 等构建产物目录也应忽略，因为它们会在容器内重新生成。

### HEALTHCHECK

健康检查让编排工具（Docker Compose、Kubernetes）和监控系统知道容器是否真正可用。没有健康检查，容器进程存在但应用无响应的情况无法被检测到。

```dockerfile
# Node.js 应用
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Python 应用（需要安装 curl）
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1
```

参数说明：
- `--interval`：检查间隔，默认 30s
- `--timeout`：单次检查超时，默认 30s
- `--start-period`：容器启动后的宽限期，期间失败不计入重试次数
- `--retries`：连续失败几次后标记为 unhealthy

### 层缓存优化

Docker 按层构建，某一层变化会导致其后所有层缓存失效。利用这一点，将变化频率低的层放前面：

```dockerfile
# 第一步：只复制依赖声明文件（变化频率低）
COPY package.json package-lock.json ./
RUN npm ci

# 第二步：复制源码（变化频率高）
COPY . .

# 第三步：构建
RUN npm run build
```

这样，修改源码时，依赖安装层的缓存仍然有效，大幅缩短构建时间。对于 Python 项目同理：先复制 `requirements.txt` 并 `pip install`，再复制源码。

## docker-compose.yml 编排

### 基本结构

```yaml
services:
  app:
    build: .
    ports:
      - "3000:3000"
    restart: unless-stopped
    env_file: .env
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    networks:
      - app-network

  db:
    image: postgres:16-alpine
    volumes:
      - db-data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

  redis:
    image: redis:7-alpine
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

networks:
  app-network:
    driver: bridge

volumes:
  db-data:
  redis-data:
```

关键要点：
- `restart: unless-stopped`：容器异常退出时自动重启，手动停止后不会自动启动
- `env_file: .env`：从文件加载环境变量，避免在 compose 文件中硬编码敏感信息
- `depends_on` + `condition: service_healthy`：确保依赖服务健康后才启动当前服务
- 每个服务都配置 `healthcheck`，形成完整的健康监控链

### 数据库服务

**PostgreSQL**

```yaml
db:
  image: postgres:16-alpine
  volumes:
    - db-data:/var/lib/postgresql/data
  environment:
    POSTGRES_DB: myapp
    POSTGRES_USER: appuser
    POSTGRES_PASSWORD: secretpassword
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U appuser -d myapp"]
    interval: 10s
    timeout: 5s
    retries: 5
```

**MySQL**

```yaml
db:
  image: mysql:8.0
  volumes:
    - db-data:/var/lib/mysql
  environment:
    MYSQL_ROOT_PASSWORD: rootpassword
    MYSQL_DATABASE: myapp
    MYSQL_USER: appuser
    MYSQL_PASSWORD: secretpassword
  healthcheck:
    test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
    interval: 10s
    timeout: 5s
    retries: 5
```

**MongoDB**

```yaml
mongo:
  image: mongo:7
  volumes:
    - mongo-data:/data/db
  environment:
    MONGO_INITDB_ROOT_USERNAME: appuser
    MONGO_INITDB_ROOT_PASSWORD: secretpassword
```

**Redis**

```yaml
redis:
  image: redis:7-alpine
  volumes:
    - redis-data:/data
  command: redis-server --appendonly yes
  healthcheck:
    test: ["CMD", "redis-cli", "ping"]
    interval: 10s
    timeout: 5s
    retries: 5
```

### 网络和卷

**命名卷（Named Volumes）**：用于持久化数据，Docker 自动管理存储位置，适合数据库数据、用户上传文件等需要长期保留的数据。

```yaml
volumes:
  db-data:        # 数据库数据
  uploads:        # 用户上传文件
```

**绑定挂载（Bind Mounts）**：将宿主机目录直接映射到容器内，适合开发环境实时同步代码。

```yaml
services:
  app:
    volumes:
      - .:/app           # 开发时代码实时同步
      - /app/node_modules  # 防止宿主机 node_modules 覆盖容器内的
```

**桥接网络（Bridge Network）**：同一网络内的容器可以通过服务名互相访问。例如 app 服务可以通过 `db:5432` 连接数据库，无需知道容器 IP。

```yaml
networks:
  app-network:
    driver: bridge
```

## 常用命令

```bash
# 构建并后台启动所有服务
docker compose up -d --build

# 查看服务状态（含健康状态）
docker compose ps

# 查看实时日志（可指定服务名）
docker compose logs -f
docker compose logs -f app

# 重启单个服务
docker compose restart app

# 停止并移除所有容器和网络
docker compose down

# 停止并移除容器、网络和卷（警告：会删除数据库数据）
docker compose down -v

# 进入运行中的容器调试
docker compose exec app sh

# 查看镜像大小
docker images

# 清理所有未使用的镜像、容器、网络
docker system prune -a

# 查看磁盘占用
docker system df
```

## 常见问题

### 构建失败

- **Dockerfile 语法错误**：逐行检查指令拼写和参数格式
- **.dockerignore 遗漏**：确认 `package.json` 等必要文件未被忽略
- **构建时网络问题**：安装依赖时无法访问外网，检查代理配置或使用镜像源
- **基础镜像不存在**：确认镜像标签正确，尝试 `docker pull` 手动拉取

### 容器启动后立即退出

```bash
# 查看退出日志
docker compose logs app

# 常见原因：
# 1. CMD/ENTRYPOINT 命令不存在或路径错误
# 2. 环境变量缺失导致应用启动失败
# 3. 端口被占用
# 4. 配置文件路径不正确
```

### 端口冲突

宿主机端口已被占用时，修改映射的宿主机端口即可：

```yaml
# 将宿主机 3001 映射到容器 3000
ports:
  - "3001:3000"
```

### 卷权限问题

容器内的非 root 用户可能无法写入挂载的卷。解决方案：

```dockerfile
# 方案一：在 Dockerfile 中创建与宿主机相同的用户 ID
RUN adduser -u 1000 -S appuser

# 方案二：在 entrypoint 脚本中动态修复权限
RUN chown -R appuser:appgroup /app/data
```

### 磁盘空间不足

```bash
# 查看磁盘占用分布
docker system df

# 清理未使用的资源（镜像、容器、网络）
docker system prune -a

# 单独清理未使用的卷
docker volume prune

# 查看具体卷的大小
docker system df -v
```
