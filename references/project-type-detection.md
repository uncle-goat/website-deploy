# Project Type Detection Guide

> A quick reference for AI to detect project types, database requirements, and recommend deployment methods.

---

## Detection Rules Explained

Project type is determined by scanning the project root directory for key files (`package.json`, `requirements.txt`, `composer.json`, `go.mod`, `pom.xml`, etc.) and their dependencies.

### Node.js Projects

| Detection Condition | Project Type | Category | Default Port | Build Command | Start Command |
|---|---|---|---|---|---|
| `package.json` + `next` | Next.js | fullstack | 3000 | `next build` | `next start` |
| `package.json` + `nuxt` | Nuxt.js | fullstack | 3000 | `nuxt build` | `nuxt start` |
| `package.json` + `express` | Express API | api | 3000 | — | `node src/index.js` |
| `package.json` + `@nestjs/core` | NestJS API | api | 3000 | — | `npm run start:prod` |
| `package.json` + `vue` (no next/nuxt) | Vue SPA | static | — | `vite build` | — |
| `package.json` + `react` (no next/nuxt) | React SPA | static | — | `npm run build` | — |
| `package.json` + `@angular/core` | Angular SPA | static | — | `ng build` | — |
| `package.json` + `svelte` | Svelte App | static | — | `svelte-kit build` | — |
| `package.json` + `astro` | Astro | static/SSR | — | `astro build` | `astro dev` |
| Only `package.json` (no framework) | Generic Node.js | api | 3000 | — | `npm start` |

**SPA output directory notes:**
- Vue / Svelte / Astro → `dist/`
- React (CRA) → `build/`
- React (Vite) → `dist/`
- Angular → `dist/<project-name>/`

### Python Projects

| Detection Condition | Project Type | Category | Default Port | Start Command |
|---|---|---|---|---|
| `requirements.txt` / `pyproject.toml` + `django` | Django | api/fullstack | 8000 | `python manage.py runserver` or `gunicorn` |
| `requirements.txt` / `pyproject.toml` + `fastapi` | FastAPI | api | 8000 | `uvicorn main:app --host 0.0.0.0` |
| `requirements.txt` / `pyproject.toml` + `flask` | Flask | api | 5000 | `flask run` or `gunicorn` |

### PHP Projects

| Detection Condition | Project Type | Category | Default Port |
|---|---|---|---|
| `composer.json` + `laravel` | Laravel | fullstack | 8000 |
| `composer.json` + `wordpress` | WordPress | cms | 80 |
| `wp-config.php` exists | WordPress | cms | 80 |

### Go Projects

| Detection Condition | Project Type | Category | Default Port | Build Command |
|---|---|---|---|---|
| `go.mod` exists | Go Binary | api/static | 8080 | `go build -o app .` |

### Java Projects

| Detection Condition | Project Type | Category | Default Port |
|---|---|---|---|
| `pom.xml` / `build.gradle` + `spring-boot` | Spring Boot | api/fullstack | 8080 |

### Static Sites

| Detection Condition | Project Type | Category |
|---|---|---|
| `index.html` exists and no `package.json` | Pure Static Site | static |
| `hugo.toml` / `config.toml` exists (Hugo) | Hugo Site | static |
| `_config.yml` exists (Jekyll) | Jekyll Site | static |

---

## Database Detection

Database requirements are determined by scanning ORM configuration files and dependencies.

| ORM / Framework | Detection File | Detection Method |
|---|---|---|
| Prisma | `prisma/schema.prisma` | Read the `provider` field: `postgresql` / `mysql` / `sqlite` |
| TypeORM | `ormconfig.json` / `data-source.ts` | Read the `type` field |
| Sequelize | `config/database.js` or `.env` | Check the `dialect` configuration |
| Mongoose | `package.json` contains `mongoose` | Always MongoDB |
| SQLAlchemy | `alembic.ini` / `models/` | Check the database type in the connection string |
| Django | `settings.py` | Read `DATABASES['default']['ENGINE']` |

**When a database is detected, set `has_database = true` and record the database type (postgresql/mysql/sqlite/mongodb).**

---

## Recommended Deployment Method Logic

Based on the project type and database requirements, recommend a deployment method using the following priority:

```
if has_database == true AND docker is available:
    → Recommend "docker" (database + application orchestrated together)

elif type == "static":
    → Recommend "static" (Nginx serves static files)

elif type == "cms":
    → docker available → Recommend "docker"
    → otherwise → Recommend "server"

elif type == "api" AND has_database == false:
    → Recommend "server" (single service, no need for containerization, simpler)

elif type == "fullstack":
    → docker available → Recommend "docker"
    → otherwise → Recommend "server"

else:
    → Default to "server"
```

**Deployment method descriptions:**
- **docker** — Generates `Dockerfile` + `docker-compose.yml`, suitable for projects with databases or multiple services
- **static** — Deploys static files directly to Nginx, suitable for SPAs and pure static sites
- **server** — Runs directly on the server, suitable for simple API services without a database
