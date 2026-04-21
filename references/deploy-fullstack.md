# Full-Stack Application Deployment Guide

## Next.js Deployment

### Standalone Output Mode

Standalone mode is the officially recommended deployment method by Next.js. It bundles all dependencies into a standalone directory, eliminating the need for a full `node_modules` and significantly reducing deployment size.

**Why use Standalone mode:**
- Bundles all required dependencies into the `.next/standalone/` directory
- No need to upload the full `node_modules` (typically hundreds of MB)
- Deployment package size can be reduced from hundreds of MB to tens of MB
- Faster startup with more controlled dependencies

**Configuration:**

Add the following to `next.config.js`:

```js
module.exports = {
  output: 'standalone',
};
```

**Build output overview:**
- `.next/standalone/` — Contains the self-contained Node.js server (`server.js`)
- `.next/static/` — Static asset files (CSS, JS, images, etc.), must be served separately
- `public/` — Public static files, must be served separately

> **Note:** `.next/static/` and `public/` are not automatically included in the standalone directory. You need to manually copy them into `standalone/public/`, or serve them directly via Nginx.

### Docker Deployment (Recommended)

Use a multi-stage build, modifying based on the `Dockerfile.node` template:

```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Run stage
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

EXPOSE 3000
CMD ["node", "server.js"]
```

**docker-compose.yml with PostgreSQL:**

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

### Server Deployment (Without Docker)

**Build and start:**

```bash
# Build
npm run build

# Manage the process with PM2
pm2 start npm --name "nextjs" -- start

# Or start the standalone server directly
node .next/standalone/server.js
```

**Systemd service configuration (`/etc/systemd/system/nextjs.service`):**

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

**Nginx reverse proxy configuration:**

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

### Environment Variable Handling

**Variable categories:**

| Type | Prefix | Accessible From | Purpose |
|------|--------|-----------------|---------|
| Public variables | `NEXT_PUBLIC_*` | Client + Server | API URLs, site name |
| Private variables | No prefix | Server only | Database passwords, API keys |

**Key rules:**
- **Never** place secrets or passwords in `NEXT_PUBLIC_*` variables, as they will be exposed to the browser
- Sensitive information such as `DATABASE_URL` and `JWT_SECRET` should use variables without a prefix
- Docker environment: use `env_file: .env` in `docker-compose.yml`
- Server environment: use `EnvironmentFile=/path/to/.env` in systemd

### Database Migration

**Prisma:**

```bash
# Run migrations before deployment
npx prisma migrate deploy

# Do not use prisma db push in production
```

**Drizzle:**

```bash
# Push schema changes
npm run db:push

# Or use migration files
drizzle-kit migrate
```

**Best practices:**
- Run migrations as a separate step; do not include them in the application startup command
- The application should not start if migration fails
- In Docker, use an entrypoint script to run migrations before starting the application:

```bash
#!/bin/sh
npx prisma migrate deploy
exec node server.js
```

---

## Nuxt.js Deployment

### Nitro Presets

Nitro is the server engine for Nuxt 3, providing multiple deployment presets:

- `node-server` — Generates a Node.js server (default deployment preset)
- `docker` — Automatically generates a Dockerfile
- `static` — Generates a purely static site (SSG mode)

**Configuration:**

```ts
// nuxt.config.ts
export default defineNuxtConfig({
  nitro: {
    preset: 'node-server',
  },
});
```

### Docker Deployment

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

**Build output overview:**
- `.output/` — Contains the complete server and public assets
- `.output/server/index.mjs` — Entry file
- `.output/public/` — Static assets

**Environment variables:**
- `NUXT_PUBLIC_*` — Accessible from the client
- Variables without prefix — Accessible from the server only
- The rules are the same as Next.js; be sure to distinguish between public and private variables

### Server Deployment

```bash
# Build
npm run build

# Start with PM2
pm2 start .output/server/index.mjs --name "nuxt"

# Or use ecosystem.config.js
module.exports = {
  apps: [{
    name: 'nuxt',
    script: '.output/server/index.mjs',
    env: { HOST: '0.0.0.0', PORT: 3000 },
  }],
};
```

The Nginx reverse proxy configuration is similar to Next.js; simply point `proxy_pass` to the port Nuxt is listening on.
