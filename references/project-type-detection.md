# 项目类型检测指南

> 供 AI 检测项目类型、数据库需求及推荐部署方式的快速参考。

---

## 检测规则详解

通过扫描项目根目录的关键文件（`package.json`、`requirements.txt`、`composer.json`、`go.mod`、`pom.xml` 等）及其依赖项来判断项目类型。

### Node.js 项目

| 检测条件 | 项目类型 | 分类 | 默认端口 | 构建命令 | 启动命令 |
|---|---|---|---|---|---|
| `package.json` + `next` | Next.js | fullstack | 3000 | `next build` | `next start` |
| `package.json` + `nuxt` | Nuxt.js | fullstack | 3000 | `nuxt build` | `nuxt start` |
| `package.json` + `express` | Express API | api | 3000 | — | `node src/index.js` |
| `package.json` + `@nestjs/core` | NestJS API | api | 3000 | — | `npm run start:prod` |
| `package.json` + `vue`（无 next/nuxt） | Vue SPA | static | — | `vite build` | — |
| `package.json` + `react`（无 next/nuxt） | React SPA | static | — | `npm run build` | — |
| `package.json` + `@angular/core` | Angular SPA | static | — | `ng build` | — |
| `package.json` + `svelte` | Svelte App | static | — | `svelte-kit build` | — |
| `package.json` + `astro` | Astro | static/SSR | — | `astro build` | `astro dev` |
| 仅有 `package.json`（无框架） | Generic Node.js | api | 3000 | — | `npm start` |

**SPA 输出目录说明：**
- Vue / Svelte / Astro → `dist/`
- React (CRA) → `build/`
- React (Vite) → `dist/`
- Angular → `dist/<project-name>/`

### Python 项目

| 检测条件 | 项目类型 | 分类 | 默认端口 | 启动命令 |
|---|---|---|---|---|
| `requirements.txt` / `pyproject.toml` + `django` | Django | api/fullstack | 8000 | `python manage.py runserver` 或 `gunicorn` |
| `requirements.txt` / `pyproject.toml` + `fastapi` | FastAPI | api | 8000 | `uvicorn main:app --host 0.0.0.0` |
| `requirements.txt` / `pyproject.toml` + `flask` | Flask | api | 5000 | `flask run` 或 `gunicorn` |

### PHP 项目

| 检测条件 | 项目类型 | 分类 | 默认端口 |
|---|---|---|---|
| `composer.json` + `laravel` | Laravel | fullstack | 8000 |
| `composer.json` + `wordpress` | WordPress | cms | 80 |
| `wp-config.php` 存在 | WordPress | cms | 80 |

### Go 项目

| 检测条件 | 项目类型 | 分类 | 默认端口 | 构建命令 |
|---|---|---|---|---|
| `go.mod` 存在 | Go Binary | api/static | 8080 | `go build -o app .` |

### Java 项目

| 检测条件 | 项目类型 | 分类 | 默认端口 |
|---|---|---|---|
| `pom.xml` / `build.gradle` + `spring-boot` | Spring Boot | api/fullstack | 8080 |

### 静态站点

| 检测条件 | 项目类型 | 分类 |
|---|---|---|
| 存在 `index.html` 且无 `package.json` | 纯静态站点 | static |
| 存在 `hugo.toml` / `config.toml`（Hugo） | Hugo 站点 | static |
| 存在 `_config.yml`（Jekyll） | Jekyll 站点 | static |

---

## 数据库检测

通过扫描 ORM 配置文件和依赖项来判断数据库需求。

| ORM / 框架 | 检测文件 | 判断方式 |
|---|---|---|
| Prisma | `prisma/schema.prisma` | 读取 `provider` 字段：`postgresql` / `mysql` / `sqlite` |
| TypeORM | `ormconfig.json` / `data-source.ts` | 读取 `type` 字段 |
| Sequelize | `config/database.js` 或 `.env` | 检查 `dialect` 配置 |
| Mongoose | `package.json` 含 `mongoose` | 固定为 MongoDB |
| SQLAlchemy | `alembic.ini` / `models/` | 检查连接字符串中的数据库类型 |
| Django | `settings.py` | 读取 `DATABASES['default']['ENGINE']` |

**检测到数据库时设置 `has_database = true`，同时记录数据库类型（postgresql/mysql/sqlite/mongodb）。**

---

## 推荐部署方式逻辑

根据项目类型和数据库需求，按以下优先级推荐部署方式：

```
if has_database == true AND docker 可用:
    → 推荐 "docker"（数据库 + 应用统一编排）

elif type == "static":
    → 推荐 "static"（Nginx 托管静态文件）

elif type == "cms":
    → docker 可用 → 推荐 "docker"
    → 否则 → 推荐 "server"

elif type == "api" AND has_database == false:
    → 推荐 "server"（单服务无需容器化，更简单）

elif type == "fullstack":
    → docker 可用 → 推荐 "docker"
    → 否则 → 推荐 "server"

else:
    → 默认推荐 "server"
```

**部署方式说明：**
- **docker** — 生成 `Dockerfile` + `docker-compose.yml`，适合有数据库或多服务场景
- **static** — 直接部署静态文件到 Nginx，适合 SPA 和纯静态站点
- **server** — 直接在服务器上运行，适合无数据库的简单 API 服务
