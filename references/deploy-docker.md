# Docker Containerized Deployment Guide

## Why Choose Docker

Docker solves many pain points of traditional deployment through containerization technology:

- **Environment consistency:** Development, testing, and production environments are fully consistent, eliminating the "it works on my machine" problem. Images package the application and all its dependencies, so the result is identical no matter where they run.
- **Isolation:** Each container has its own filesystem, network stack, and process space. Applications do not interfere with each other, and different runtime versions can safely run on the same host.
- **Easy scaling:** Combined with Docker Compose or Kubernetes, service instances can be quickly scaled horizontally to handle traffic spikes.
- **Reproducible builds:** The Dockerfile serves as build documentation. Anyone can build the exact same image from the same Dockerfile at any time.
- **Clean teardown:** A single `docker compose down` command removes all containers and networks with no leftovers, which is ideal for temporary environments and CI/CD scenarios.

## Dockerfile Best Practices

### Multi-Stage Builds

The core idea of multi-stage builds: the final image contains only the files needed at runtime, excluding build tools, source code, etc. A typical unoptimized Node.js project image may be 500MB+, but after multi-stage builds it is usually only 50-100MB.

```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Run
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

# Copy only production dependencies and build artifacts
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public

EXPOSE 3000
USER node
CMD ["node", "dist/server.js"]
```

The same principle applies to Python projects:

```dockerfile
# Stage 1: Build
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Stage 2: Run
FROM python:3.12-slim AS runner
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY . .
EXPOSE 8000
CMD ["gunicorn", "app:app", "-b", "0.0.0.0:8000"]
```

### Non-root User

By default, containers run as root. If a container is compromised, the attacker gains root privileges on the host. Creating a dedicated user is the most basic security hardening measure.

```dockerfile
# Create user and group
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Set working directory and transfer ownership
WORKDIR /app
COPY --chown=appuser:appgroup . .

# Switch to non-root user
USER appuser

EXPOSE 3000
CMD ["node", "dist/server.js"]
```

If the application needs to listen on port 80, do not run it as root. Instead, map the container port to the host's port 80: `docker run -p 80:3000 ...`.

### .dockerignore

`.dockerignore` prevents unnecessary files from entering the build context, speeding up builds and reducing image size:

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

For multi-stage builds, build output directories such as `dist` should also be ignored since they will be regenerated inside the container.

### HEALTHCHECK

Health checks allow orchestration tools (Docker Compose, Kubernetes) and monitoring systems to know whether a container is truly available. Without health checks, situations where the container process exists but the application is unresponsive cannot be detected.

```dockerfile
# Node.js application
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Python application (requires curl to be installed)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1
```

Parameter descriptions:
- `--interval`: Check interval, default 30s
- `--timeout`: Timeout for a single check, default 30s
- `--start-period`: Grace period after container startup; failures during this period do not count toward retries
- `--retries`: Number of consecutive failures before marking as unhealthy

### Layer Cache Optimization

Docker builds in layers. A change in one layer invalidates the cache for all subsequent layers. Taking advantage of this, place layers that change less frequently first:

```dockerfile
# Step 1: Copy only dependency declaration files (low change frequency)
COPY package.json package-lock.json ./
RUN npm ci

# Step 2: Copy source code (high change frequency)
COPY . .

# Step 3: Build
RUN npm run build
```

This way, when source code changes, the dependency installation layer cache remains valid, significantly reducing build time. The same principle applies to Python projects: copy `requirements.txt` and run `pip install` first, then copy the source code.

## docker-compose.yml Orchestration

### Basic Structure

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

Key points:
- `restart: unless-stopped`: Automatically restarts the container on abnormal exit, but does not auto-start after a manual stop
- `env_file: .env`: Loads environment variables from a file, avoiding hardcoding sensitive information in the compose file
- `depends_on` + `condition: service_healthy`: Ensures dependent services are healthy before starting the current service
- Each service has a `healthcheck` configured, forming a complete health monitoring chain

### Database Services

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

### Networks and Volumes

**Named Volumes:** Used for persistent data. Docker automatically manages the storage location. Suitable for database data, user uploads, and other data that needs long-term retention.

```yaml
volumes:
  db-data:        # Database data
  uploads:        # User uploaded files
```

**Bind Mounts:** Map a host directory directly into the container. Suitable for real-time code synchronization in development environments.

```yaml
services:
  app:
    volumes:
      - .:/app           # Real-time code sync during development
      - /app/node_modules  # Prevent host node_modules from overwriting container's
```

**Bridge Network:** Containers within the same network can access each other by service name. For example, the app service can connect to the database via `db:5432` without knowing the container's IP.

```yaml
networks:
  app-network:
    driver: bridge
```

## Common Commands

```bash
# Build and start all services in the background
docker compose up -d --build

# View service status (including health status)
docker compose ps

# View real-time logs (can specify a service name)
docker compose logs -f
docker compose logs -f app

# Restart a single service
docker compose restart app

# Stop and remove all containers and networks
docker compose down

# Stop and remove containers, networks, and volumes (warning: deletes database data)
docker compose down -v

# Enter a running container for debugging
docker compose exec app sh

# View image sizes
docker images

# Clean up all unused images, containers, and networks
docker system prune -a

# View disk usage
docker system df
```

## Common Issues

### Build Failure

- **Dockerfile syntax error:** Check instruction spelling and parameter format line by line
- **Missing .dockerignore:** Ensure necessary files like `package.json` are not being ignored
- **Network issues during build:** Unable to access the internet when installing dependencies; check proxy configuration or use a mirror source
- **Base image does not exist:** Verify the image tag is correct; try `docker pull` to manually pull it

### Container Exits Immediately After Starting

```bash
# View exit logs
docker compose logs app

# Common causes:
# 1. CMD/ENTRYPOINT command does not exist or has an incorrect path
# 2. Missing environment variables causing application startup failure
# 3. Port is already in use
# 4. Configuration file path is incorrect
```

### Port Conflict

When the host port is already in use, simply change the mapped host port:

```yaml
# Map host port 3001 to container port 3000
ports:
  - "3001:3000"
```

### Volume Permission Issues

A non-root user inside the container may not be able to write to mounted volumes. Solutions:

```dockerfile
# Option 1: Create a user with the same UID as the host in the Dockerfile
RUN adduser -u 1000 -S appuser

# Option 2: Dynamically fix permissions in the entrypoint script
RUN chown -R appuser:appgroup /app/data
```

### Insufficient Disk Space

```bash
# View disk usage distribution
docker system df

# Clean up unused resources (images, containers, networks)
docker system prune -a

# Clean up unused volumes separately
docker volume prune

# View specific volume sizes
docker system df -v
```
