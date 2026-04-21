#!/bin/bash
set -euo pipefail

# ============================================================================
# detect-project-type.sh
# Scans a directory and outputs structured JSON describing the project type.
# ============================================================================

TARGET_DIR="${1:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# ---------------------------------------------------------------------------
# Helper: safely read a JSON-like string value from a file using grep+sed.
# Usage: read_json_value <file> <key>
# Returns the raw value (stripped of surrounding quotes) or empty string.
# ---------------------------------------------------------------------------
read_json_value() {
    local file="$1" key="$2"
    if [ ! -f "$file" ]; then
        return
    fi
    # Match "key": "value" or "key":'value' — tolerant of whitespace
    local val
    val="$(grep -oP "\"${key}\"\s*:\s*\"[^\"]*\"" "$file" 2>/dev/null | head -1 | sed 's/.*:.*"\(.*\)"/\1/' || true)"
    printf '%s' "$val"
}

# ---------------------------------------------------------------------------
# Helper: check if a JSON file contains a top-level key (object key).
# Usage: json_has_key <file> <key>
# Returns 0 (true) if the key exists, 1 otherwise.
# ---------------------------------------------------------------------------
json_has_key() {
    local file="$1" key="$2"
    if [ ! -f "$file" ]; then
        return 1
    fi
    grep -qP "\"${key}\"\s*:" "$file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Helper: check if a dependency name appears in package.json dependencies or
# devDependencies. Matches word boundaries so "express" won't match "expresso".
# ---------------------------------------------------------------------------
pkg_has_dep() {
    local file="$1" dep="$2"
    if [ ! -f "$file" ]; then
        return 1
    fi
    # We look for the dep name followed by a colon inside deps/devDeps blocks.
    # Simple approach: grep for the dep as a key in a JSON object.
    grep -qP "\"${dep}\"\s*:" "$file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Helper: check if a script name exists in the "scripts" object.
# ---------------------------------------------------------------------------
pkg_has_script() {
    local file="$1" script="$2"
    if [ ! -f "$file" ]; then
        return 1
    fi
    # Find the scripts block and look for the script key
    # Simple: just grep for "scriptname": inside the file (good enough for most cases)
    grep -qP "\"${script}\"\s*:" "$file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Helper: check if a string contains a substring
# ---------------------------------------------------------------------------
str_contains() {
    local haystack="$1" needle="$2"
    [ -n "$haystack" ] && printf '%s' "$haystack" | grep -qF "$needle"
}

# ---------------------------------------------------------------------------
# Helper: escape a string for JSON output
# ---------------------------------------------------------------------------
json_escape() {
    local str="$1"
    # Escape backslash and double quote
    printf '%s' "$str" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# ---------------------------------------------------------------------------
# Helper: read a single-line value from a config file (KEY=VALUE or KEY VALUE)
# ---------------------------------------------------------------------------
read_config_value() {
    local file="$1" key="$2"
    if [ ! -f "$file" ]; then
        return
    fi
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null | head -1 | sed "s/^[^=]*=//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true
}

# ============================================================================
# Initialise detection variables
# ============================================================================
TYPE="unknown"
LANGUAGE="unknown"
FRAMEWORK=""
FRAMEWORK_VERSION=""
PACKAGE_MANAGER=""
BUILD_COMMAND=""
START_COMMAND=""
OUTPUT_DIR=""
HAS_DATABASE=false
DATABASE_TYPE=""
PORT=""
ENV_EXAMPLE=""
DOCKERFILE_EXISTS=false
DOCKER_COMPOSE_EXISTS=false
RECOMMENDED_DEPLOY=""

# ============================================================================
# 1. Dockerfile detection
# ============================================================================
if [ -f "$TARGET_DIR/Dockerfile" ]; then
    DOCKERFILE_EXISTS=true
fi

# ============================================================================
# 2. docker-compose detection
# ============================================================================
if [ -f "$TARGET_DIR/docker-compose.yml" ] || [ -f "$TARGET_DIR/docker-compose.yaml" ]; then
    DOCKER_COMPOSE_EXISTS=true
fi

# ============================================================================
# 3. Node.js / package.json detection
# ============================================================================
PKG_JSON="$TARGET_DIR/package.json"
if [ -f "$PKG_JSON" ]; then
    LANGUAGE="nodejs"

    # --- Framework detection (order matters: more specific first) ---
    # Detect build tool first — if a client-side build tool exists without an
    # SSR framework, the project is a static SPA, not fullstack.
    HAS_SSR_FRAMEWORK=false
    IS_SPA_BUILDER=false

    # Check for SPA build tool config files
    if [ -f "$TARGET_DIR/vite.config.ts" ] || [ -f "$TARGET_DIR/vite.config.js" ]; then
        IS_SPA_BUILDER=true
    fi
    if [ -f "$TARGET_DIR/craco.config.js" ] || [ -f "$TARGET_DIR/craco.config.ts" ]; then
        IS_SPA_BUILDER=true
    fi

    if pkg_has_dep "$PKG_JSON" "next"; then
        FRAMEWORK="Next.js"
        FRAMEWORK_VERSION="$(read_json_value "$PKG_JSON" "next" 2>/dev/null || true)"
        TYPE="fullstack"
        HAS_SSR_FRAMEWORK=true
        OUTPUT_DIR=".next"
    elif pkg_has_dep "$PKG_JSON" "nuxt"; then
        FRAMEWORK="Nuxt.js"
        FRAMEWORK_VERSION="$(read_json_value "$PKG_JSON" "nuxt" 2>/dev/null || true)"
        TYPE="fullstack"
        HAS_SSR_FRAMEWORK=true
        OUTPUT_DIR=".output"
    elif pkg_has_dep "$PKG_JSON" "@angular/core"; then
        FRAMEWORK="Angular"
        FRAMEWORK_VERSION="$(read_json_value "$PKG_JSON" "@angular/core" 2>/dev/null || true)"
        TYPE="static"
        OUTPUT_DIR="dist"
    elif pkg_has_dep "$PKG_JSON" "nestjs" || pkg_has_dep "$PKG_JSON" "@nestjs/core"; then
        FRAMEWORK="NestJS"
        FRAMEWORK_VERSION="$(read_json_value "$PKG_JSON" "@nestjs/core" 2>/dev/null || true)"
        TYPE="api"
        OUTPUT_DIR="dist"
    elif pkg_has_dep "$PKG_JSON" "express"; then
        FRAMEWORK="Express"
        FRAMEWORK_VERSION="$(read_json_value "$PKG_JSON" "express" 2>/dev/null || true)"
        TYPE="api"
    elif pkg_has_dep "$PKG_JSON" "astro"; then
        FRAMEWORK="Astro"
        FRAMEWORK_VERSION="$(read_json_value "$PKG_JSON" "astro" 2>/dev/null || true)"
        TYPE="static"
        OUTPUT_DIR="dist"
    elif pkg_has_dep "$PKG_JSON" "svelte"; then
        FRAMEWORK="Svelte"
        FRAMEWORK_VERSION="$(read_json_value "$PKG_JSON" "svelte" 2>/dev/null || true)"
        TYPE="static"
        OUTPUT_DIR="build"
    elif pkg_has_dep "$PKG_JSON" "vue"; then
        FRAMEWORK="Vue"
        FRAMEWORK_VERSION="$(read_json_value "$PKG_JSON" "vue" 2>/dev/null || true)"
        TYPE="static"
        OUTPUT_DIR="dist"
    elif pkg_has_dep "$PKG_JSON" "react"; then
        FRAMEWORK="React"
        FRAMEWORK_VERSION="$(read_json_value "$PKG_JSON" "react" 2>/dev/null || true)"
        # React alone (no Next.js) is a client-side library, not a framework.
        # With a build tool (Vite, CRA, etc.) it produces a static SPA.
        TYPE="static"
        OUTPUT_DIR="dist"
    fi

    # If a SPA build tool was detected but type is still generic, ensure static
    if $IS_SPA_BUILDER && [ "$TYPE" = "unknown" ]; then
        TYPE="static"
        OUTPUT_DIR="dist"
    fi

    # --- Scripts ---
    if pkg_has_script "$PKG_JSON" "build"; then
        BUILD_COMMAND="npm run build"
    fi
    if pkg_has_script "$PKG_JSON" "start"; then
        START_COMMAND="npm start"
    elif pkg_has_script "$PKG_JSON" "dev"; then
        START_COMMAND="npm run dev"
    fi

    # --- Package manager ---
    if [ -f "$TARGET_DIR/pnpm-lock.yaml" ]; then
        PACKAGE_MANAGER="pnpm"
        # Adjust commands for pnpm
        if [ -n "$BUILD_COMMAND" ]; then BUILD_COMMAND="pnpm build"; fi
        if [ -n "$START_COMMAND" ]; then START_COMMAND="pnpm start"; fi
    elif [ -f "$TARGET_DIR/yarn.lock" ]; then
        PACKAGE_MANAGER="yarn"
        if [ -n "$BUILD_COMMAND" ]; then BUILD_COMMAND="yarn build"; fi
        if [ -n "$START_COMMAND" ]; then START_COMMAND="yarn start"; fi
    elif [ -f "$TARGET_DIR/package-lock.json" ]; then
        PACKAGE_MANAGER="npm"
    else
        PACKAGE_MANAGER="npm"
    fi

    # --- Database detection ---
    if pkg_has_dep "$PKG_JSON" "prisma" || pkg_has_dep "$PKG_JSON" "@prisma/client"; then
        HAS_DATABASE=true
    fi
    if pkg_has_dep "$PKG_JSON" "typeorm"; then
        HAS_DATABASE=true
    fi
    if pkg_has_dep "$PKG_JSON" "sequelize"; then
        HAS_DATABASE=true
    fi
    if pkg_has_dep "$PKG_JSON" "mongoose"; then
        HAS_DATABASE=true
        DATABASE_TYPE="mongodb"
    fi
    if pkg_has_dep "$PKG_JSON" "pg" || pkg_has_dep "$PKG_JSON" "postgres"; then
        DATABASE_TYPE="postgresql"
        HAS_DATABASE=true
    fi
    if pkg_has_dep "$PKG_JSON" "mysql" || pkg_has_dep "$PKG_JSON" "mysql2"; then
        DATABASE_TYPE="mysql"
        HAS_DATABASE=true
    fi
    if pkg_has_dep "$PKG_JSON" "redis" || pkg_has_dep "$PKG_JSON" "ioredis"; then
        if [ -z "$DATABASE_TYPE" ]; then
            DATABASE_TYPE="redis"
        fi
        HAS_DATABASE=true
    fi
    if pkg_has_dep "$PKG_JSON" "better-sqlite3" || pkg_has_dep "$PKG_JSON" "sql.js"; then
        if [ -z "$DATABASE_TYPE" ]; then
            DATABASE_TYPE="sqlite"
        fi
        HAS_DATABASE=true
    fi

    # --- Port inference ---
    # Check package.json scripts for port hints
    local_scripts="$(grep -oP '"scripts"\s*:\s*\{[^}]*\}' "$PKG_JSON" 2>/dev/null || true)"
    if str_contains "$local_scripts" "3000"; then
        PORT="3000"
    elif str_contains "$local_scripts" "8080"; then
        PORT="8080"
    elif str_contains "$local_scripts" "5000"; then
        PORT="5000"
    elif str_contains "$local_scripts" "4000"; then
        PORT="4000"
    fi
    # Check next.config for port
    if [ -z "$PORT" ]; then
        for ncfg in "$TARGET_DIR"/next.config.* "$TARGET_DIR"/next.config; do
            if [ -f "$ncfg" ]; then
                ncfg_content="$(cat "$ncfg" 2>/dev/null || true)"
                if str_contains "$ncfg_content" "3000"; then
                    PORT="3000"
                fi
                break
            fi
        done
    fi
fi

# ============================================================================
# 4. Python detection
# ============================================================================
REQUIREMENTS="$TARGET_DIR/requirements.txt"
PYPROJECT="$TARGET_DIR/pyproject.toml"
SETUP_PY="$TARGET_DIR/setup.py"

if [ -f "$REQUIREMENTS" ] || [ -f "$PYPROJECT" ] || [ -f "$SETUP_PY" ]; then
    # Only override language if not already set by Node.js
    if [ "$LANGUAGE" = "unknown" ]; then
        LANGUAGE="python"
    fi
    PACKAGE_MANAGER="pip"

    # Framework detection
    if [ -f "$REQUIREMENTS" ]; then
        if grep -qiE "django" "$REQUIREMENTS" 2>/dev/null; then
            FRAMEWORK="Django"
            TYPE="fullstack"
            HAS_DATABASE=true
            DATABASE_TYPE="postgresql"
            START_COMMAND="python manage.py runserver"
            PORT="8000"
            django_version="$(grep -iE "^django[><=!~]" "$REQUIREMENTS" 2>/dev/null | head -1 | grep -oP '[\d.]+' | head -1 || true)"
            if [ -n "$django_version" ]; then
                FRAMEWORK_VERSION="$django_version"
            fi
        fi
        if grep -qiE "flask" "$REQUIREMENTS" 2>/dev/null; then
            if [ -z "$FRAMEWORK" ]; then
                FRAMEWORK="Flask"
                TYPE="api"
                START_COMMAND="flask run"
                PORT="5000"
                flask_version="$(grep -iE "^flask[><=!~]" "$REQUIREMENTS" 2>/dev/null | head -1 | grep -oP '[\d.]+' | head -1 || true)"
                if [ -n "$flask_version" ]; then
                    FRAMEWORK_VERSION="$flask_version"
                fi
            fi
        fi
        if grep -qiE "fastapi" "$REQUIREMENTS" 2>/dev/null; then
            if [ -z "$FRAMEWORK" ]; then
                FRAMEWORK="FastAPI"
                TYPE="api"
                START_COMMAND="uvicorn main:app --host 0.0.0.0 --port 8000"
                PORT="8000"
                fastapi_version="$(grep -iE "^fastapi[><=!~]" "$REQUIREMENTS" 2>/dev/null | head -1 | grep -oP '[\d.]+' | head -1 || true)"
                if [ -n "$fastapi_version" ]; then
                    FRAMEWORK_VERSION="$fastapi_version"
                fi
            fi
        fi

        # Database detection
        if grep -qiE "psycopg|postgresql|asyncpg" "$REQUIREMENTS" 2>/dev/null; then
            HAS_DATABASE=true
            DATABASE_TYPE="postgresql"
        fi
        if grep -qiE "pymysql|mysqlclient" "$REQUIREMENTS" 2>/dev/null; then
            HAS_DATABASE=true
            if [ -z "$DATABASE_TYPE" ]; then
                DATABASE_TYPE="mysql"
            fi
        fi
        if grep -qiE "pymongo|motor" "$REQUIREMENTS" 2>/dev/null; then
            HAS_DATABASE=true
            if [ -z "$DATABASE_TYPE" ]; then
                DATABASE_TYPE="mongodb"
            fi
        fi
        if grep -qiE "redis" "$REQUIREMENTS" 2>/dev/null; then
            HAS_DATABASE=true
            if [ -z "$DATABASE_TYPE" ]; then
                DATABASE_TYPE="redis"
            fi
        fi
        if grep -qiE "sqlalchemy" "$REQUIREMENTS" 2>/dev/null; then
            HAS_DATABASE=true
        fi
    fi

    # Also check pyproject.toml for dependencies
    if [ -f "$PYPROJECT" ]; then
        pyproject_content="$(cat "$PYPROJECT" 2>/dev/null || true)"
        if str_contains "$pyproject_content" "django" && [ -z "$FRAMEWORK" ]; then
            FRAMEWORK="Django"
            TYPE="fullstack"
            HAS_DATABASE=true
            DATABASE_TYPE="postgresql"
            START_COMMAND="python manage.py runserver"
            PORT="8000"
        fi
        if str_contains "$pyproject_content" "flask" && [ -z "$FRAMEWORK" ]; then
            FRAMEWORK="Flask"
            TYPE="api"
            START_COMMAND="flask run"
            PORT="5000"
        fi
        if str_contains "$pyproject_content" "fastapi" && [ -z "$FRAMEWORK" ]; then
            FRAMEWORK="FastAPI"
            TYPE="api"
            START_COMMAND="uvicorn main:app --host 0.0.0.0 --port 8000"
            PORT="8000"
        fi
        if str_contains "$pyproject_content" "sqlalchemy"; then
            HAS_DATABASE=true
        fi
    fi

    # Build command for Python
    if [ -z "$BUILD_COMMAND" ]; then
        if [ -f "$PYPROJECT" ] && grep -q "setuptools\|hatchling\|poetry-core" "$PYPROJECT" 2>/dev/null; then
            BUILD_COMMAND="pip install -e ."
        fi
    fi
fi

# ============================================================================
# 5. PHP / composer.json detection
# ============================================================================
COMPOSER_JSON="$TARGET_DIR/composer.json"
if [ -f "$COMPOSER_JSON" ]; then
    if [ "$LANGUAGE" = "unknown" ]; then
        LANGUAGE="php"
    fi
    PACKAGE_MANAGER="composer"

    if pkg_has_dep "$COMPOSER_JSON" "laravel/laravel" || pkg_has_dep "$COMPOSER_JSON" "laravel/framework"; then
        FRAMEWORK="Laravel"
        TYPE="fullstack"
        HAS_DATABASE=true
        START_COMMAND="php artisan serve"
        PORT="8000"
        OUTPUT_DIR="public"
        laravel_ver="$(read_json_value "$COMPOSER_JSON" "laravel/framework" 2>/dev/null || true)"
        if [ -n "$laravel_ver" ]; then
            FRAMEWORK_VERSION="$laravel_ver"
        fi
    elif pkg_has_dep "$COMPOSER_JSON" "wordpress" || pkg_has_dep "$COMPOSER_JSON" "wp-core"; then
        FRAMEWORK="WordPress"
        TYPE="cms"
        PORT="80"
    elif pkg_has_dep "$COMPOSER_JSON" "symfony"; then
        FRAMEWORK="Symfony"
        TYPE="fullstack"
        PORT="8000"
    fi
fi

# ============================================================================
# 6. Go detection
# ============================================================================
GO_MOD="$TARGET_DIR/go.mod"
if [ -f "$GO_MOD" ]; then
    if [ "$LANGUAGE" = "unknown" ]; then
        LANGUAGE="go"
    fi
    PACKAGE_MANAGER="go"
    TYPE="api"
    BUILD_COMMAND="go build -o bin/app ."
    START_COMMAND="./bin/app"
    PORT="8080"

    # Try to detect framework from go.mod
    go_content="$(cat "$GO_MOD" 2>/dev/null || true)"
    if str_contains "$go_content" "gin-gonic/gin"; then
        FRAMEWORK="Gin"
    elif str_contains "$go_content" "gorilla/mux"; then
        FRAMEWORK="Gorilla Mux"
    elif str_contains "$go_content" "labstack/echo"; then
        FRAMEWORK="Echo"
    elif str_contains "$go_content" "go-chi/chi"; then
        FRAMEWORK="Chi"
    elif str_contains "$go_content" "fiber/fiber"; then
        FRAMEWORK="Fiber"
    fi

    # Database detection from go.mod
    if str_contains "$go_content" "lib/pq" || str_contains "$go_content" "jackc/pgx"; then
        HAS_DATABASE=true
        DATABASE_TYPE="postgresql"
    fi
    if str_contains "$go_content" "go-sql-driver/mysql"; then
        HAS_DATABASE=true
        if [ -z "$DATABASE_TYPE" ]; then
            DATABASE_TYPE="mysql"
        fi
    fi
    if str_contains "$go_content" "mongodb/mongo-go-driver" || str_contains "$go_content" "go.mongodb.org/mongo-driver"; then
        HAS_DATABASE=true
        if [ -z "$DATABASE_TYPE" ]; then
            DATABASE_TYPE="mongodb"
        fi
    fi
    if str_contains "$go_content" "redis/go-redis"; then
        HAS_DATABASE=true
        if [ -z "$DATABASE_TYPE" ]; then
            DATABASE_TYPE="redis"
        fi
    fi
    if str_contains "$go_content" "gorm.io/gorm"; then
        HAS_DATABASE=true
    fi
fi

# ============================================================================
# 7. Java detection
# ============================================================================
POM_XML="$TARGET_DIR/pom.xml"
BUILD_GRADLE="$TARGET_DIR/build.gradle"
BUILD_GRADLE_KTS="$TARGET_DIR/build.gradle.kts"

if [ -f "$POM_XML" ]; then
    if [ "$LANGUAGE" = "unknown" ]; then
        LANGUAGE="java"
    fi
    PACKAGE_MANAGER="maven"
    TYPE="api"
    BUILD_COMMAND="mvn clean package"
    START_COMMAND="java -jar target/*.jar"
    PORT="8080"
    OUTPUT_DIR="target"

    pom_content="$(cat "$POM_XML" 2>/dev/null || true)"
    if str_contains "$pom_content" "spring-boot"; then
        FRAMEWORK="Spring Boot"
        TYPE="fullstack"
    elif str_contains "$pom_content" "spring-core"; then
        FRAMEWORK="Spring"
    elif str_contains "$pom_content" "quarkus"; then
        FRAMEWORK="Quarkus"
    elif str_contains "$pom_content" "micronaut"; then
        FRAMEWORK="Micronaut"
    fi

    # Database
    if str_contains "$pom_content" "postgresql"; then
        HAS_DATABASE=true
        DATABASE_TYPE="postgresql"
    fi
    if str_contains "$pom_content" "mysql-connector"; then
        HAS_DATABASE=true
        if [ -z "$DATABASE_TYPE" ]; then
            DATABASE_TYPE="mysql"
        fi
    fi
    if str_contains "$pom_content" "mongodb" || str_contains "$pom_content" "spring-data-mongodb"; then
        HAS_DATABASE=true
        if [ -z "$DATABASE_TYPE" ]; then
            DATABASE_TYPE="mongodb"
        fi
    fi
    if str_contains "$pom_content" "hibernate" || str_contains "$pom_content" "spring-data-jpa"; then
        HAS_DATABASE=true
    fi
fi

if [ -f "$BUILD_GRADLE" ] || [ -f "$BUILD_GRADLE_KTS" ]; then
    if [ "$LANGUAGE" = "unknown" ]; then
        LANGUAGE="java"
    fi
    PACKAGE_MANAGER="gradle"
    TYPE="api"
    BUILD_COMMAND="./gradlew build"
    START_COMMAND="./gradlew bootRun"
    PORT="8080"
    OUTPUT_DIR="build/libs"

    gradle_content="$(cat "$BUILD_GRADLE" 2>/dev/null || cat "$BUILD_GRADLE_KTS" 2>/dev/null || true)"
    if str_contains "$gradle_content" "spring-boot"; then
        FRAMEWORK="Spring Boot"
        TYPE="fullstack"
    elif str_contains "$gradle_content" "kotlin" && str_contains "$gradle_content" "ktor"; then
        FRAMEWORK="Ktor"
    fi
fi

# ============================================================================
# 8. WordPress (wp-config.php)
# ============================================================================
if [ -f "$TARGET_DIR/wp-config.php" ]; then
    if [ "$LANGUAGE" = "unknown" ]; then
        LANGUAGE="php"
    fi
    if [ -z "$FRAMEWORK" ]; then
        FRAMEWORK="WordPress"
    fi
    TYPE="cms"
    PORT="80"
    HAS_DATABASE=true
    DATABASE_TYPE="mysql"
fi

# ============================================================================
# 9. Ghost CMS detection
# ============================================================================
CONFIG_PRODUCTION="$TARGET_DIR/config.production.json"
if [ -f "$CONFIG_PRODUCTION" ]; then
    config_content="$(cat "$CONFIG_PRODUCTION" 2>/dev/null || true)"
    if str_contains "$config_content" "ghost"; then
        FRAMEWORK="Ghost"
        TYPE="cms"
        PORT="2368"
        if [ "$LANGUAGE" = "unknown" ]; then
            LANGUAGE="nodejs"
        fi
        if [ "$PACKAGE_MANAGER" = "" ]; then
            PACKAGE_MANAGER="npm"
        fi
        HAS_DATABASE=true
        DATABASE_TYPE="mysql"
    fi
fi

# ============================================================================
# 10. Static HTML/CSS/JS detection
# ============================================================================
if [ "$LANGUAGE" = "unknown" ] && [ "$TYPE" = "unknown" ]; then
    has_html=false
    has_css=false
    has_js=false

    # Check for HTML files
    html_count="$(find "$TARGET_DIR" -maxdepth 2 -name '*.html' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$html_count" -gt 0 ]; then
        has_html=true
    fi

    # Check for CSS files
    css_count="$(find "$TARGET_DIR" -maxdepth 2 -name '*.css' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$css_count" -gt 0 ]; then
        has_css=true
    fi

    # Check for JS files (but not package.json context)
    js_count="$(find "$TARGET_DIR" -maxdepth 2 -name '*.js' -not -path '*/node_modules/*' -not -path '*/.git/*' -not -name 'package*.json' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$js_count" -gt 0 ]; then
        has_js=true
    fi

    if $has_html || $has_css || $has_js; then
        LANGUAGE="static"
        TYPE="static"
        PORT="80"
    fi
fi

# ============================================================================
# .env.example detection
# ============================================================================
if [ -f "$TARGET_DIR/.env.example" ]; then
    ENV_EXAMPLE=".env.example"
elif [ -f "$TARGET_DIR/.env.local.example" ]; then
    ENV_EXAMPLE=".env.local.example"
elif [ -f "$TARGET_DIR/.env.sample" ]; then
    ENV_EXAMPLE=".env.sample"
fi

# ============================================================================
# Port inference: check .env.example for PORT variable
# ============================================================================
if [ -z "$PORT" ] && [ -n "$ENV_EXAMPLE" ]; then
    env_port="$(read_config_value "$TARGET_DIR/$ENV_EXAMPLE" "PORT" 2>/dev/null || true)"
    if [ -n "$env_port" ]; then
        PORT="$env_port"
    fi
fi

# ============================================================================
# Recommended deploy strategy
# ============================================================================
if $DOCKERFILE_EXISTS; then
    RECOMMENDED_DEPLOY="docker"
elif [ "$TYPE" = "static" ]; then
    RECOMMENDED_DEPLOY="static"
elif [ "$TYPE" = "api" ] || [ "$TYPE" = "fullstack" ] || [ "$TYPE" = "cms" ]; then
    if $DOCKER_COMPOSE_EXISTS; then
        RECOMMENDED_DEPLOY="docker"
    else
        RECOMMENDED_DEPLOY="server"
    fi
fi

# ============================================================================
# Normalise empty strings to null for JSON
# ============================================================================
if [ -z "$FRAMEWORK" ]; then FRAMEWORK="null"; else FRAMEWORK="\"$(json_escape "$FRAMEWORK")\""; fi
if [ -z "$FRAMEWORK_VERSION" ]; then FRAMEWORK_VERSION="null"; else FRAMEWORK_VERSION="\"$(json_escape "$FRAMEWORK_VERSION")\""; fi
if [ -z "$PACKAGE_MANAGER" ]; then PACKAGE_MANAGER="null"; else PACKAGE_MANAGER="\"$(json_escape "$PACKAGE_MANAGER")\""; fi
if [ -z "$BUILD_COMMAND" ]; then BUILD_COMMAND="null"; else BUILD_COMMAND="\"$(json_escape "$BUILD_COMMAND")\""; fi
if [ -z "$START_COMMAND" ]; then START_COMMAND="null"; else START_COMMAND="\"$(json_escape "$START_COMMAND")\""; fi
if [ -z "$OUTPUT_DIR" ]; then OUTPUT_DIR="null"; else OUTPUT_DIR="\"$(json_escape "$OUTPUT_DIR")\""; fi
if [ -z "$DATABASE_TYPE" ]; then DATABASE_TYPE="null"; else DATABASE_TYPE="\"$(json_escape "$DATABASE_TYPE")\""; fi
if [ -z "$PORT" ]; then PORT="null"; else PORT="\"$(json_escape "$PORT")\""; fi
if [ -z "$ENV_EXAMPLE" ]; then ENV_EXAMPLE="null"; else ENV_EXAMPLE="\"$(json_escape "$ENV_EXAMPLE")\""; fi
if [ -z "$RECOMMENDED_DEPLOY" ]; then RECOMMENDED_DEPLOY="null"; else RECOMMENDED_DEPLOY="\"$(json_escape "$RECOMMENDED_DEPLOY")\""; fi

# ============================================================================
# Output JSON
# ============================================================================
printf '{\n'
printf '  "type": "%s",\n' "$TYPE"
printf '  "language": "%s",\n' "$LANGUAGE"
printf '  "framework": %s,\n' "$FRAMEWORK"
printf '  "framework_version": %s,\n' "$FRAMEWORK_VERSION"
printf '  "package_manager": %s,\n' "$PACKAGE_MANAGER"
printf '  "build_command": %s,\n' "$BUILD_COMMAND"
printf '  "start_command": %s,\n' "$START_COMMAND"
printf '  "output_dir": %s,\n' "$OUTPUT_DIR"
printf '  "has_database": %s,\n' "$HAS_DATABASE"
printf '  "database_type": %s,\n' "$DATABASE_TYPE"
printf '  "port": %s,\n' "$PORT"
printf '  "env_example": %s,\n' "$ENV_EXAMPLE"
printf '  "dockerfile_exists": %s,\n' "$DOCKERFILE_EXISTS"
printf '  "docker_compose_exists": %s,\n' "$DOCKER_COMPOSE_EXISTS"
printf '  "recommended_deploy": %s\n' "$RECOMMENDED_DEPLOY"
printf '}\n'
