---
name: website-deploy
description: "全自动网站部署技能，覆盖Docker容器化、传统云服务器(Nginx/systemd/SSH)、静态站点托管(Cloudflare Pages/GitHub Pages)三大部署路径。自动检测项目类型(Node.js/Python/PHP/Go/Java/静态站点)、服务器环境(OS/容器/依赖/端口/磁盘/内存)、推荐最优部署方案并一键执行。支持全栈应用(Next.js/Nuxt.js)、CMS(WordPress/Ghost)、后端API服务(Express/FastAPI/Django)等多种场景。当用户说'部署网站'、'deploy this project'、'帮我上线'、'配置Docker'、'设置Nginx'、'部署到服务器'、'配置SSL证书'、'dockerize this app'、'发布到Cloudflare Pages'、'创建GitHub Actions部署'、'更新代码'、'重新部署'、'代码更新了帮我部署'、'回滚'、'rollback'或任何涉及将项目从本地/代码仓库部署到线上可访问环境、或更新已部署项目的请求时触发。也适用于用户已有服务器但需要配置反向代理、SSL证书、systemd服务等场景。不要在仅涉及本地开发运行(project-setup)或代码编写时触发。"
---

# Website Deploy Skill

## Why This Skill Exists

Deploying a website involves dozens of moving parts: matching the right deployment strategy to the project type, detecting and installing the correct runtime versions, writing production-grade Dockerfiles with multi-stage builds and non-root users, configuring Nginx reverse proxies with proper headers, obtaining and renewing SSL certificates, setting up systemd services for process management, and verifying everything actually works. Getting any one of these steps wrong means a broken deployment — and the error messages are rarely helpful.

This skill automates the entire deployment pipeline so the AI can handle the complexity. It detects the environment and project type, recommends the optimal deployment method, generates production-ready configuration files, executes the deployment, and verifies the result. The goal is to turn "deploy my website" into a single, reliable operation.

**Boundary with project-setup**: This skill handles **production deployment** (Docker, Nginx, SSL, cloud servers, static hosting). If the user only wants to run a project locally for development, use `project-setup` instead.

## Core Workflow

```
Environment Detection → Project Type Detection → Recommend Deploy Method
        ↓                        ↓                         ↓
   [OS, Docker,          [Framework, Language,        [Docker Compose /
    Nginx, Ports,         Build Tool, DB]             Nginx+systemd /
    Disk, Memory]                                      Static Hosting]
        ↓                        ↓                         ↓
   Pre-deployment Preparation → Execute Deployment → Post-deploy Verification
   [Install deps,             [Generate configs,       [Health check,
    Check ports,               Build & start,           SSL verify,
    Env vars]                  Configure SSL]           Report URL]
```

## First Deploy vs Update Deploy

Before starting, determine whether this is a **first deployment** or an **update deployment**:

```
Is there already a running deployment on the target?
├── Yes (Docker Compose exists, or systemd service is active, or site is accessible)
│   └── This is an UPDATE deployment → Jump to Step 7: Update Deployment
└── No (fresh server, no existing configs)
    └── This is a FIRST deployment → Continue with Step 1 below
```

Detection methods:
- Docker: `docker compose ps` shows running services
- Server: `systemctl is-active <service-name>` returns active
- Remote: `curl -sf https://domain/health` returns 200
- Files: Dockerfile, docker-compose.yml, or systemd service file already exists in the project

## Step 1: Environment Detection

Run the environment detection script to gather all system information:

```bash
bash <skill-path>/scripts/detect-environment.sh
```

The script outputs structured JSON with OS details, installed tools (Docker, Nginx, Node.js, Python, PHP, etc.), resource availability (CPU, memory, disk), occupied ports, SSH configuration, and firewall status.

Based on the output, determine the **environment type**:
- **Docker-ready**: Docker and Docker Compose are installed and the daemon is running
- **Bare-metal with tools**: No Docker, but Nginx/Node.js/etc. are available or can be installed
- **Fresh server**: Minimal installation, most tools need to be installed
- **Remote SSH**: Deployment target is a remote server accessible via SSH

For detailed detection logic and output interpretation, read `references/environment-detection.md`.

## Step 2: Project Type Detection

Run the project type detection script on the project directory:

```bash
bash <skill-path>/scripts/detect-project-type.sh /path/to/project
```

The script scans for characteristic files (package.json, requirements.txt, composer.json, go.mod, etc.), identifies the framework (Next.js, Nuxt.js, Express, Django, Flask, etc.), infers build/start commands, port numbers, and database requirements.

The output includes a `recommended_deploy` field suggesting the best deployment method. For detailed detection rules, read `references/project-type-detection.md`.

## Step 3: Deployment Method Recommendation

Based on the environment and project type, recommend a deployment method using this decision matrix:

| Project Type | Docker Available | Recommended Method |
|---|---|---|
| Full-stack (Next.js/Nuxt.js) | Yes | Docker Compose (app + DB) |
| Full-stack (Next.js/Nuxt.js) | No | Nginx + systemd + PM2 |
| Static site / SPA | Any | Cloudflare Pages / GitHub Pages |
| CMS (WordPress/Ghost) | Yes | Docker Compose (CMS + DB + Redis) |
| CMS (WordPress/Ghost) | No | Nginx + PHP-FPM + MySQL |
| Backend API | Yes | Docker Compose (API + DB) |
| Backend API | No | Nginx + systemd + Gunicorn/uWSGI |

Use `AskUserQuestion` to confirm the deployment method with the user before proceeding. Present the recommendation with a brief explanation of why it suits their project.

## Step 4: Pre-deployment Preparation

Before deploying, ensure the environment is ready:

1. **Install missing dependencies** — Run `scripts/install-dependencies.sh` for any tools the deployment method requires. Read `references/dependency-installation.md` for supported tools and mirror source configuration.

2. **Run the pre-deploy checklist** — Verify environment variables are set, ports are available, disk space is sufficient, DNS is configured (if using a domain), and the build succeeds locally. Read `references/pre-deploy-checklist.md` for the complete checklist.

3. **Generate configuration files** — Based on the chosen deployment method, prepare the necessary configs:
   - Docker path: Dockerfile + docker-compose.yml + .env
   - Server path: Nginx config + systemd service + .env
   - Static path: GitHub Actions workflow or wrangler config

## Step 5: Execute Deployment

Follow the appropriate deployment path. Each path has a detailed reference document — read it before executing.

### Path A: Docker Containerization

Read `references/deploy-docker.md` for the complete guide.

Key actions:
1. Generate Dockerfile using `scripts/generate-dockerfile.sh --type <nodejs|python|php|static> --port <port>`
2. Generate docker-compose.yml using `scripts/generate-docker-compose.sh` (adds database services if needed)
3. Review and adjust the generated files (especially environment variables)
4. Build and start: `docker compose up -d --build`
5. Check container status: `docker compose ps` and `docker compose logs -f`

### Path B: Traditional Cloud Server (Nginx + systemd)

Read `references/deploy-server.md` for the complete guide.

Key actions:
1. Generate Nginx config: `scripts/generate-nginx-config.sh --type reverse-proxy --domain <domain> --upstream <host:port>`
2. Generate systemd service: `scripts/generate-systemd-service.sh --name <name> --exec <command>`
3. Build the project (npm run build / python setup, etc.)
4. Enable and start the service: `systemctl enable --now <name>`
5. Test Nginx config: `nginx -t && systemctl reload nginx`

For SSL, run `scripts/setup-ssl.sh --domain <domain> --email <email> --nginx`. Read `references/ssl-certificates.md` for details.

### Path C: Static Site Hosting

Read `references/deploy-static.md` for the complete guide.

For **Cloudflare Pages**: Guide the user through connecting their Git repo or use `wrangler pages deploy`.
For **GitHub Pages**: Generate a GitHub Actions workflow from `templates/github-actions-deploy.yml` and commit it to the repo.

### Special Scenarios

- **Full-stack apps (Next.js/Nuxt.js)**: Read `references/deploy-fullstack.md` for standalone output mode, environment variable handling, and database migration strategies.
- **CMS (WordPress/Ghost)**: Read `references/deploy-cms.md` for Docker Compose setups with persistent storage and backup strategies.
- **Backend APIs**: Read `references/deploy-api.md` for PM2/Gunicorn configuration, API health endpoints, and documentation generation.

## Step 6: Post-deployment Verification

After deployment, verify everything is working:

```bash
bash <skill-path>/scripts/health-check.sh --url <url> --expected-status 200
```

The health check script tests HTTP status, SSL certificate validity, response time, and optionally checks for expected content on the page.

Read `references/post-deploy-verification.md` for the complete verification checklist.

**Report the result to the user** including:
- Access URL (HTTP and HTTPS if SSL was configured)
- Admin/login URLs (if applicable)
- Any credentials generated during setup
- Important notes (e.g., SSL renewal is automatic, how to view logs, how to update)

## Decision Framework

When the user's request doesn't fit neatly into the workflow above, use this quick decision tree:

```
Is there an existing Dockerfile or docker-compose.yml?
├── Yes → Enhance it (add multi-stage build, non-root user, health check) and deploy
└── No → Detect project type
    ├── Static site (HTML/CSS/JS, Vite, CRA, Hugo, Jekyll)
    │   └── Deploy to Cloudflare Pages or GitHub Pages
    ├── Full-stack (Next.js, Nuxt.js, Remix)
    │   ├── Docker available → Docker Compose with standalone output
    │   └── No Docker → Nginx + systemd + PM2
    ├── CMS (WordPress, Ghost)
    │   └── Docker Compose (WordPress + MySQL + Redis)
    ├── Backend API (Express, FastAPI, Django, Flask)
    │   ├── Docker available → Docker Compose (API + DB)
    │   └── No Docker → Nginx + systemd + Gunicorn/uWSGI
    └── Unknown / Custom
        └── Ask the user for more details
```

## Step 7: Update Deployment (Code Updated → Redeploy)

When the user says "代码更新了", "帮我重新部署", "update the server", or similar, follow this workflow. **This step replaces Steps 1-6 for existing deployments.** Read `references/update-deploy.md` for the complete guide.

### Phase 1: Pre-update Safety (MUST NOT SKIP)

1. **Backup current version** — Create a timestamped backup before any changes:
   - Docker: `docker save` the current app image to a backup file
   - Server: `tar -czf backup-$(date +%Y%m%d%H%M%S).tar.gz` the app directory (exclude node_modules, .git, venv)
   - Database: `mysqldump` / `pg_dump` / `mongodump` if this update includes schema changes
   - Keep only the last 3 backups, auto-delete older ones

2. **Check what changed** — `git diff --stat HEAD~1` or `git log --oneline -5` to understand the scope of changes. Specifically check:
   - Are there new migration files? (prisma/migrations/, migrations/, alembic/)
   - Are there new environment variables? (compare .env.example with current .env)
   - Are there dependency changes? (package.json, requirements.txt, etc.)

3. **Pre-flight check** — Verify the deployment environment is still healthy:
   - Disk space >= 2GB free
   - Current service is running and healthy (curl health endpoint)
   - Docker daemon running (if Docker deployment)

### Phase 2: Execute Update

Run the automated update script or execute manually:

```bash
# Automated (recommended):
bash <skill-path>/scripts/update-deploy.sh --method <docker|server|ssh> --app-dir /path/to/app [--health-url https://domain/health]
```

Or execute manually in this exact order:

**Docker path:**
1. `git pull origin main`
2. Compare `.env.example` with `.env` — add any new variables
3. `docker compose build --no-cache app` (rebuild only the app, not the database)
4. `docker compose up -d --build app` (rolling update, database untouched)
5. Wait for healthy: `docker compose ps` (check health status)
6. Run migrations if needed: `docker compose exec app npx prisma migrate deploy`

**Server path:**
1. `git pull origin main`
2. `npm ci --production` (or `pip install -r requirements.txt`)
3. `npm run build`
4. Run migrations if needed: `python manage.py migrate --noinput`
5. `systemctl restart myapp`
6. Wait and verify: `sleep 3 && systemctl status myapp`

**Remote SSH path:**
1. `rsync -avz --delete --exclude='node_modules' --exclude='.git' --exclude='.env' --exclude='venv' ./ user@host:/var/www/app/`
2. `ssh user@host "cd /var/www/app && npm ci --production && npm run build && sudo systemctl restart myapp"`

### Phase 3: Post-update Verification

1. Health check: `bash <skill-path>/scripts/health-check.sh --url <url> --expected-status 200`
2. Check logs: `docker compose logs --tail=50 app` or `journalctl -u myapp --since "1 min ago"`
3. Verify no new errors in logs

### Phase 4: Cleanup (MUST NOT SKIP)

1. **Docker**: `docker image prune -f` (remove dangling images), `docker builder prune -f` (clear build cache)
2. **Server**: Remove old backups (keep last 3), clean build temp files (`rm -rf /tmp/build-*`)
3. **Logs**: `journalctl --vacuum-size=100M` (limit log size)
4. **Disk check**: `df -h` (confirm sufficient space after cleanup)

### Rollback on Failure

If the health check fails after update, **immediately rollback**:

```bash
# Docker: restore previous image
docker compose down app
docker load -i /backups/app-image-backup-YYYYMMDDHHMMSS.tar
docker compose up -d app

# Server: restore code backup
systemctl stop myapp
tar -xzf /backups/myapp-backup-YYYYMMDDHHMMSS.tar.gz -C /var/www/
npm ci --production && npm run build
systemctl start myapp

# Database: restore from dump
psql < /backups/db-backup-YYYYMMDDHHMMSS.sql
```

After rollback, run health check again and report the result to the user.

### CI/CD Auto-Deploy (Optional)

For automated deployments on every push to main, use the GitHub Actions workflow template:

```bash
cp <skill-path>/templates/github-actions-server-deploy.yml .github/workflows/deploy.yml
```

Required GitHub Secrets: `SERVER_HOST`, `SERVER_USER`, `SERVER_SSH_KEY`, `DEPLOY_URL`. The workflow includes automatic rollback on failure.

## Error Recovery

Common deployment failures and how to handle them:

| Symptom | Likely Cause | Fix |
|---|---|---|
| `docker compose up` fails to build | Missing .dockerignore, layer cache issue | Check Dockerfile, add .dockerignore, clean build cache |
| Container starts but exits immediately | Entrypoint error, missing env vars | Check `docker compose logs`, verify .env file |
| 502 Bad Gateway from Nginx | Upstream not running, wrong port | Check service status, verify proxy_pass port matches |
| SSL certificate fails | Port 80 blocked, DNS not pointing to server | Check firewall, verify DNS A record |
| Permission denied on file operations | Wrong file ownership | `chown -R` to match the service user |
| Out of memory during build | Server has <1GB RAM | Add swap space, or build locally and transfer |

For detailed troubleshooting, read `references/troubleshooting.md`.

## Reference Files Index

| File | When to Read |
|---|---|
| `references/environment-detection.md` | Understanding environment detection output and minimum requirements |
| `references/dependency-installation.md` | Installing missing tools (Docker, Nginx, Node.js, Python, etc.) |
| `references/project-type-detection.md` | Understanding how project types are identified and classified |
| `references/deploy-docker.md` | Docker containerization deployment (Dockerfile, docker-compose, best practices) |
| `references/deploy-server.md` | Traditional server deployment (Nginx reverse proxy, systemd, SSH) |
| `references/deploy-static.md` | Static site hosting (Cloudflare Pages, GitHub Pages) |
| `references/deploy-fullstack.md` | Full-stack app specifics (Next.js standalone, Nuxt.js Nitro, DB migrations) |
| `references/deploy-cms.md` | CMS deployment (WordPress, Ghost with Docker Compose) |
| `references/deploy-api.md` | Backend API deployment (PM2, Gunicorn, health endpoints) |
| `references/ssl-certificates.md` | SSL certificate setup (certbot, Let's Encrypt, auto-renewal) |
| `references/pre-deploy-checklist.md` | Complete pre-deployment verification checklist |
| `references/post-deploy-verification.md` | Post-deployment health check and verification procedures |
| `references/update-deploy.md` | **Update deployment workflow** (backup → pull → build → migrate → restart → verify → cleanup → rollback) |
| `references/troubleshooting.md` | Common errors, diagnosis steps, and fixes |
