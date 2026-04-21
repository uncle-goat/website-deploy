# 后端 API 服务部署指南

## Express.js 部署

### PM2 进程管理

PM2 是 Node.js 生产环境首选的进程管理工具，提供进程守护、自动重启、集群模式和日志管理。

**为什么选择 PM2：**
- 进程守护：进程崩溃后自动重启
- 集群模式：充分利用多核 CPU
- 日志管理：统一管理应用日志
- 负载监控：实时查看 CPU 和内存占用

**安装：**
```bash
npm install -g pm2
```

**启动应用：**
```bash
# 基本启动
pm2 start src/index.js --name api --env production

# 集群模式（使用所有 CPU 核心）
pm2 start src/index.js -i max --name api

# 指定实例数量
pm2 start src/index.js -i 4 --name api
```

**常用命令：**
```bash
pm2 list          # 查看所有进程
pm2 logs api      # 查看日志
pm2 restart api   # 重启应用
pm2 stop api      # 停止应用
pm2 delete api    # 删除应用
pm2 monit         # 实时监控面板
pm2 info api      # 查看详细信息
```

**开机自启：**
```bash
pm2 startup       # 生成启动脚本
pm2 save          # 保存当前进程列表
```

### systemd 部署（替代 PM2）

如果不使用 PM2，可以直接用 systemd 管理服务。

**使用生成脚本：**
```bash
bash generate-systemd-service.sh --name my-api --user deploy --workdir /opt/app --command "/usr/bin/node /path/to/app/src/index.js"
```

**手动创建服务文件：**
```ini
# /etc/systemd/system/my-api.service
[Unit]
Description=My API Service
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/opt/app
ExecStart=/usr/bin/node /opt/app/src/index.js
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

**使用 PM2 Ecosystem 配置文件：**
```javascript
// ecosystem.config.js
module.exports = {
  apps: [{
    name: 'api',
    script: 'src/index.js',
    instances: 'max',
    exec_mode: 'cluster',
    env_production: {
      NODE_ENV: 'production',
      PORT: 3000
    }
  }]
};
```

```bash
pm2 start ecosystem.config.js --env production
```

---

## FastAPI 部署

### Gunicorn + Uvicorn Workers

Uvicorn 是 ASGI 服务器，Gunicorn 负责管理多个 worker 进程，两者结合适合生产环境。

**为什么使用 Gunicorn + Uvicorn：**
- Uvicorn：高性能 ASGI 服务器，支持异步
- Gunicorn：成熟的进程管理器，支持平滑重启、优雅关闭
- 多 worker 进程充分利用多核 CPU

**启动命令：**
```bash
gunicorn app.main:app \
  -w 4 \
  -k uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:8000 \
  --access-logfile - \
  --error-logfile - \
  --log-level info
```

**Worker 数量建议：**
- 公式：(2 × CPU 核心数) + 1
- 4 核服务器：9 个 worker
- 2 核服务器：5 个 worker

**systemd 服务配置：**
```ini
# /etc/systemd/system/fastapi.service
[Unit]
Description=FastAPI Application
After=network.target

[Service]
Type=notify
User=deploy
WorkingDirectory=/opt/app
ExecStart=/opt/app/venv/bin/gunicorn app.main:app \
  -w 4 \
  -k uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

### Docker 部署

**Dockerfile（使用 Dockerfile.python 模板）：**
```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

EXPOSE 8000

CMD ["gunicorn", "app.main:app", \
     "-w", "4", \
     "-k", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000"]

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1
```

---

## Django 部署

### Gunicorn

Django 使用 WSGI 协议，通过 Gunicorn 运行。

**启动命令：**
```bash
gunicorn myproject.wsgi:application \
  --bind 0.0.0.0:8000 \
  --workers 3 \
  --timeout 120 \
  --access-logfile - \
  --error-logfile -
```

**部署前准备：**
```bash
# 收集静态文件
python manage.py collectstatic --noinput

# 执行数据库迁移
python manage.py migrate --noinput
```

**Nginx 配置要点：**
- 静态文件由 Nginx 直接提供（`STATIC_ROOT`）
- 媒体文件由 Nginx 直接提供（`MEDIA_ROOT`）
- 动态请求通过反向代理转发到 Gunicorn

### Docker 部署

**入口脚本（entrypoint.sh）：**
```bash
#!/bin/bash
set -e

echo "Running database migrations..."
python manage.py migrate --noinput

echo "Collecting static files..."
python manage.py collectstatic --noinput

echo "Starting Gunicorn..."
exec gunicorn myproject.wsgi:application \
  --bind 0.0.0.0:8000 \
  --workers 3
```

**Docker Compose 卷挂载：**
```yaml
volumes:
  - static_data:/app/staticfiles
  - media_data:/app/mediafiles
```

---

## API 健康检查端点

所有 API 服务都应实现健康检查端点，返回 200 OK。

**检查内容：**
- 数据库连接状态
- 缓存连接状态（Redis 等）
- 外部服务可用性（如需依赖）
- 应用版本号

**响应示例：**
```json
{
  "status": "healthy",
  "database": "connected",
  "cache": "connected",
  "version": "1.0.0",
  "uptime": 86400
}
```

**FastAPI 实现：**
```python
@app.get("/health")
async def health_check():
    return {"status": "healthy", "version": "1.0.0"}
```

**Express 实现：**
```javascript
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', version: '1.0.0' });
});
```

---

## API 文档

- **FastAPI**：自动生成，访问 `/docs`（Swagger UI）和 `/redoc`（ReDoc）
- **Express**：使用 `swagger-ui-express` 和 `swagger-jsdoc` 生成
- **Django**：使用 `drf-spectacular` 或 `drf-yasg` 自动生成 OpenAPI 文档
