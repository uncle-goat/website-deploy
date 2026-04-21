# 全栈应用部署指南

## Next.js 部署

### Standalone 输出模式

Standalone 模式是 Next.js 官方推荐的部署方式，它将所有依赖打包到一个独立目录中，无需完整的 `node_modules`，大幅减小部署体积。

**为什么使用 Standalone 模式：**
- 将所有必需依赖打包到 `.next/standalone/` 目录
- 无需上传完整的 `node_modules`（通常数百 MB）
- 部署包体积可从数百 MB 缩减至几十 MB
- 启动更快，依赖更可控

**配置方式：**

在 `next.config.js` 中添加：

```js
module.exports = {
  output: 'standalone',
};
```

**构建产物说明：**
- `.next/standalone/` — 包含自包含的 Node.js 服务器（`server.js`）
- `.next/static/` — 静态资源文件（CSS、JS、图片等），需单独提供
- `public/` — 公共静态文件，需单独提供

> **注意：** `.next/static/` 和 `public/` 不会自动包含在 standalone 目录中，需要手动复制到 `standalone/public/` 下，或通过 Nginx 直接提供。

### Docker 部署（推荐）

使用多阶段构建，基于 `Dockerfile.node` 模板进行修改：

```dockerfile
# 构建阶段
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# 运行阶段
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

EXPOSE 3000
CMD ["node", "server.js"]
```

**docker-compose.yml 配合 PostgreSQL：**

```yaml
version: '3.8'
services:
  app:
    build: .
    ports:
      - "3000:3000"
    env_file: .env
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user -d myapp"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  db-data:
```

### 服务器部署（无 Docker）

**构建与启动：**

```bash
# 构建
npm run build

# 使用 PM2 管理进程
pm2 start npm --name "nextjs" -- start

# 或直接启动 standalone 服务器
node .next/standalone/server.js
```

**Systemd 服务配置（`/etc/systemd/system/nextjs.service`）：**

```ini
[Unit]
Description=Next.js Application
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/var/www/myapp
ExecStart=/usr/bin/node .next/standalone/server.js
EnvironmentFile=/var/www/myapp/.env
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**Nginx 反向代理配置：**

```nginx
server {
    listen 80;
    server_name example.com;

    location /_next/static/ {
        alias /var/www/myapp/.next/static/;
        expires 365d;
        access_log off;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_cache_bypass $http_upgrade;
    }
}
```

### 环境变量处理

**变量分类：**

| 类型 | 前缀 | 可访问位置 | 用途 |
|------|------|-----------|------|
| 公开变量 | `NEXT_PUBLIC_*` | 客户端 + 服务端 | API 地址、站点名称 |
| 私有变量 | 无前缀 | 仅服务端 | 数据库密码、API 密钥 |

**关键规则：**
- **永远不要**将密钥、密码放在 `NEXT_PUBLIC_*` 变量中，它们会暴露给浏览器
- `DATABASE_URL`、`JWT_SECRET` 等敏感信息使用无前缀变量
- Docker 环境：在 `docker-compose.yml` 中使用 `env_file: .env`
- 服务器环境：在 systemd 中使用 `EnvironmentFile=/path/to/.env`

### 数据库迁移

**Prisma：**

```bash
# 部署前执行迁移
npx prisma migrate deploy

# 生产环境不要使用 prisma db push
```

**Drizzle：**

```bash
# 推送 schema 变更
npm run db:push

# 或使用迁移文件
drizzle-kit migrate
```

**最佳实践：**
- 迁移作为独立步骤执行，不要放在应用启动命令中
- 迁移失败时不应启动应用
- 在 Docker 中使用 entrypoint 脚本先执行迁移再启动：

```bash
#!/bin/sh
npx prisma migrate deploy
exec node server.js
```

---

## Nuxt.js 部署

### Nitro 预设

Nitro 是 Nuxt 3 的服务端引擎，提供多种部署预设：

- `node-server` — 生成 Node.js 服务器（默认部署预设）
- `docker` — 自动生成 Dockerfile
- `static` — 生成纯静态站点（SSG 模式）

**配置方式：**

```ts
// nuxt.config.ts
export default defineNuxtConfig({
  nitro: {
    preset: 'node-server',
  },
});
```

### Docker 部署

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/.output ./
EXPOSE 3000
ENV HOST=0.0.0.0
ENV PORT=3000
CMD ["node", "server/index.mjs"]
```

**构建产物说明：**
- `.output/` — 包含完整的服务端和公共资源
- `.output/server/index.mjs` — 入口文件
- `.output/public/` — 静态资源

**环境变量：**
- `NUXT_PUBLIC_*` — 客户端可访问
- 无前缀变量 — 仅服务端可访问
- 规则与 Next.js 相同，注意区分公开与私有变量

### 服务器部署

```bash
# 构建
npm run build

# PM2 启动
pm2 start .output/server/index.mjs --name "nuxt"

# 或使用 ecosystem.config.js
module.exports = {
  apps: [{
    name: 'nuxt',
    script: '.output/server/index.mjs',
    env: { HOST: '0.0.0.0', PORT: 3000 },
  }],
};
```

Nginx 反向代理配置与 Next.js 类似，将 `proxy_pass` 指向 Nuxt 监听的端口即可。
