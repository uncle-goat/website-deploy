#!/bin/bash
set -euo pipefail

###############################################################################
# update-deploy.sh - Automated Update Deployment Script
#
# Usage: bash update-deploy.sh --method <docker|server|ssh> [options]
#
# Options:
#   --method docker|server|ssh  (required) Deployment method
#   --app-dir /path/to/app      (required) Application directory
#   --service-name name         (for server method) systemd service name
#   --remote-user user          (for ssh method) SSH user
#   --remote-host host          (for ssh method) SSH host
#   --remote-dir /path          (for ssh method) Remote app directory
#   --backup-dir /path          (default: /var/www/backups) Backup directory
#   --skip-backup               Skip backup step (not recommended)
#   --skip-migration            Skip database migration
#   --health-url url            Health check URL
#   --verbose                   Show detailed output
###############################################################################

# ── Color & Logging ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

VERBOSE=false
LOG_FILE=""

log()       { echo -e "$(timestamp) ${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "$(timestamp) ${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "$(timestamp) ${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "$(timestamp) ${RED}[ERROR]${NC} $*" >&2; }
log_phase() { echo -e "\n$(timestamp) ${CYAN}══════════════════════════════════════════════════${NC}"; echo -e "$(timestamp) ${CYAN}  $*${NC}"; echo -e "$(timestamp) ${CYAN}══════════════════════════════════════════════════${NC}"; }
log_step()  { echo -e "\n$(timestamp) ${BLUE}── $* ──${NC}"; }
log_detail(){ [[ "$VERBOSE" == true ]] && echo -e "$(timestamp)         $*"; return 0; }

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

# ── Default Values ───────────────────────────────────────────────────────────
METHOD=""
APP_DIR=""
SERVICE_NAME=""
REMOTE_USER=""
REMOTE_HOST=""
REMOTE_DIR=""
BACKUP_DIR="/var/www/backups"
SKIP_BACKUP=false
SKIP_MIGRATION=false
HEALTH_URL=""
NEEDS_MIGRATION=false
DEPLOY_PHASE=""          # Track which phase we're in for rollback decisions
CURRENT_STEP=""          # Track current step name
BACKUP_PATH=""           # Path to the backup we created
ORIGINAL_BRANCH=""       # Git branch before deploy
DEPLOY_START_TIME=""     # For summary timing

# ── Argument Parsing ─────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: bash update-deploy.sh --method <docker|server|ssh> [options]

Required:
  --method docker|server|ssh  Deployment method
  --app-dir /path/to/app      Application directory

Server method:
  --service-name name         systemd service name

SSH method:
  --remote-user user          SSH user
  --remote-host host          SSH host
  --remote-dir /path          Remote app directory

Optional:
  --backup-dir /path          Backup directory (default: /var/www/backups)
  --skip-backup               Skip backup step (not recommended)
  --skip-migration            Skip database migration
  --health-url url            Health check URL
  --verbose                   Show detailed output
  -h, --help                  Show this help message
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --method)        METHOD="$2";        shift 2 ;;
            --app-dir)       APP_DIR="$2";       shift 2 ;;
            --service-name)  SERVICE_NAME="$2";  shift 2 ;;
            --remote-user)   REMOTE_USER="$2";   shift 2 ;;
            --remote-host)   REMOTE_HOST="$2";   shift 2 ;;
            --remote-dir)    REMOTE_DIR="$2";    shift 2 ;;
            --backup-dir)    BACKUP_DIR="$2";    shift 2 ;;
            --skip-backup)   SKIP_BACKUP=true;   shift ;;
            --skip-migration) SKIP_MIGRATION=true; shift ;;
            --health-url)    HEALTH_URL="$2";    shift 2 ;;
            --verbose)       VERBOSE=true;       shift ;;
            -h|--help)       usage ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done
}

# ── Validation ───────────────────────────────────────────────────────────────
validate_args() {
    if [[ -z "$METHOD" ]]; then
        log_error "Missing required option: --method"
        exit 1
    fi
    if [[ -z "$APP_DIR" ]]; then
        log_error "Missing required option: --app-dir"
        exit 1
    fi
    if [[ ! -d "$APP_DIR" ]]; then
        log_error "Application directory does not exist: $APP_DIR"
        exit 1
    fi

    case "$METHOD" in
        docker) ;;
        server)
            if [[ -z "$SERVICE_NAME" ]]; then
                log_error "Server method requires --service-name"
                exit 1
            fi
            ;;
        ssh)
            if [[ -z "$REMOTE_USER" || -z "$REMOTE_HOST" || -z "$REMOTE_DIR" ]]; then
                log_error "SSH method requires --remote-user, --remote-host, and --remote-dir"
                exit 1
            fi
            ;;
        *)
            log_error "Invalid method: $METHOD (must be docker, server, or ssh)"
            exit 1
            ;;
    esac

    mkdir -p "$BACKUP_DIR"
}

# ── Utility Functions ────────────────────────────────────────────────────────
check_command() {
    if ! command -v "$1" &>/dev/null; then
        log_error "Required command not found: $1"
        exit 1
    fi
}

ssh_cmd() {
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${REMOTE_USER}@${REMOTE_HOST}" "$@"
}

rsync_cmd() {
    rsync -avz --delete -e "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10" "$@"
}

detect_project_type() {
    if [[ -f "$APP_DIR/package.json" ]]; then
        echo "node"
    elif [[ -f "$APP_DIR/requirements.txt" ]] || [[ -f "$APP_DIR/pyproject.toml" ]] || [[ -f "$APP_DIR/Pipfile" ]]; then
        echo "python"
    elif [[ -f "$APP_DIR/go.mod" ]]; then
        echo "go"
    elif [[ -f "$APP_DIR/Cargo.toml" ]]; then
        echo "rust"
    else
        echo "unknown"
    fi
}

detect_current_branch() {
    git -C "$APP_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 1: PRE-DEPLOYMENT
# ═══════════════════════════════════════════════════════════════════════════════

# ── Step 1: Pre-flight Checks ────────────────────────────────────────────────
pre_check() {
    CURRENT_STEP="pre_check"
    log_step "Step 1/11: Pre-flight checks"

    # Check required commands
    log_detail "Checking required commands..."
    check_command git
    check_command curl
    case "$METHOD" in
        docker) check_command docker ;;
        server) check_command systemctl ;;
        ssh)    check_command ssh; check_command rsync ;;
    esac

    # Check disk space (>=2GB free)
    log_detail "Checking disk space..."
    local free_space_gb
    case "$METHOD" in
        docker|server)
            free_space_gb=$(df "$APP_DIR" | awk 'NR==2 {printf "%.0f", $4/1024/1024}')
            ;;
        ssh)
            free_space_gb=$(ssh_cmd "df $REMOTE_DIR | awk 'NR==2 {printf \\\"%.0f\\\", \\$4/1024/1024}'" 2>/dev/null || echo "0")
            ;;
    esac
    log_detail "Free disk space: ${free_space_gb}GB"
    if [[ "$free_space_gb" -lt 2 ]]; then
        log_error "Insufficient disk space: ${free_space_gb}GB free (need >=2GB)"
        exit 1
    fi
    log_ok "Disk space check passed (${free_space_gb}GB free)"

    # Check service health (if health URL provided)
    if [[ -n "$HEALTH_URL" ]]; then
        log_detail "Checking current service health at $HEALTH_URL ..."
        local http_code
        http_code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$HEALTH_URL" 2>/dev/null || echo "000")
        if [[ "$http_code" =~ ^2 ]]; then
            log_ok "Service is healthy (HTTP $http_code)"
        elif [[ "$http_code" == "000" ]]; then
            log_warn "Service is not reachable (connection refused or timeout)"
            log_warn "Continuing deployment -- service may not be running yet"
        else
            log_warn "Service returned HTTP $http_code (expected 2xx)"
            log_warn "Continuing deployment -- will verify after update"
        fi
    else
        log_detail "No health URL provided, skipping health pre-check"
    fi

    # Check git status
    log_detail "Checking git status..."
    if [[ ! -d "$APP_DIR/.git" ]]; then
        log_error "Not a git repository: $APP_DIR"
        exit 1
    fi
    local git_status
    git_status=$(git -C "$APP_DIR" status --porcelain 2>/dev/null)
    if [[ -n "$git_status" ]]; then
        log_warn "Working directory has uncommitted changes:"
        echo "$git_status" | head -10 | while read -r line; do
            log_detail "  $line"
        done
        log_warn "Stashing changes before pull..."
        git -C "$APP_DIR" stash push -m "auto-stash before deploy $(date +%Y%m%d%H%M%S)" >/dev/null 2>&1 || true
    else
        log_ok "Git working directory is clean"
    fi

    ORIGINAL_BRANCH=$(detect_current_branch)
    log_detail "Current branch: $ORIGINAL_BRANCH"

    log_ok "Pre-flight checks completed"
}

# ── Step 2: Backup ───────────────────────────────────────────────────────────
backup() {
    CURRENT_STEP="backup"
    log_step "Step 2/11: Creating backup"

    if [[ "$SKIP_BACKUP" == true ]]; then
        log_warn "Backup skipped (--skip-backup flag set)"
        return 0
    fi

    local ts
    ts=$(date '+%Y%m%d_%H%M%S')

    case "$METHOD" in
        docker)
            backup_docker "$ts"
            ;;
        server)
            backup_server "$ts"
            ;;
        ssh)
            backup_ssh "$ts"
            ;;
    esac

    log_ok "Backup created: $BACKUP_PATH"
}

backup_docker() {
    local ts="$1"
    local compose_file=""

    # Find docker-compose file
    for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        if [[ -f "$APP_DIR/$f" ]]; then
            compose_file="$APP_DIR/$f"
            break
        fi
    done

    if [[ -z "$compose_file" ]]; then
        log_warn "No docker-compose file found, skipping Docker image backup"
        return 0
    fi

    # Get the app service image name
    local app_image
    app_image=$(docker compose -f "$compose_file" config --images 2>/dev/null | head -1 || echo "")
    if [[ -z "$app_image" ]]; then
        log_warn "Could not determine Docker image name, skipping image backup"
        return 0
    fi

    BACKUP_PATH="$BACKUP_DIR/${app_image//\//_}_${ts}.tar"
    log_detail "Saving Docker image: $app_image -> $BACKUP_PATH"
    docker save -o "$BACKUP_PATH" "$app_image" 2>/dev/null
    log_detail "Image saved: $(du -h "$BACKUP_PATH" | cut -f1)"
}

backup_server() {
    local ts="$1"
    BACKUP_PATH="$BACKUP_DIR/app_backup_${ts}.tar.gz"

    log_detail "Creating tar.gz backup: $BACKUP_PATH"
    tar -czf "$BACKUP_PATH" \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='venv' \
        --exclude='.venv' \
        --exclude='__pycache__' \
        --exclude='.next' \
        --exclude='dist' \
        --exclude='build' \
        --exclude='*.pyc' \
        --exclude='.env.local' \
        -C "$(dirname "$APP_DIR")" \
        "$(basename "$APP_DIR")" 2>/dev/null
    log_detail "Backup created: $(du -h "$BACKUP_PATH" | cut -f1)"
}

backup_ssh() {
    local ts="$1"
    BACKUP_PATH="/tmp/remote_backup_${ts}.tar.gz"

    log_detail "Creating remote backup on $REMOTE_HOST ..."
    ssh_cmd "cd $(dirname "$REMOTE_DIR") && tar -czf $BACKUP_PATH \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='venv' \
        --exclude='.venv' \
        --exclude='__pycache__' \
        --exclude='.next' \
        --exclude='dist' \
        --exclude='build' \
        --exclude='*.pyc' \
        $(basename "$REMOTE_DIR") 2>/dev/null"
    log_detail "Remote backup created: $BACKUP_PATH"
}

# ── Step 3: Check Changes ────────────────────────────────────────────────────
check_changes() {
    CURRENT_STEP="check_changes"
    log_step "Step 3/11: Checking for changes"

    local remote_branch="origin/$ORIGINAL_BRANCH"

    # Fetch latest info
    log_detail "Fetching remote info..."
    git -C "$APP_DIR" fetch origin "$ORIGINAL_BRANCH" --quiet 2>/dev/null || true

    # Check what changed
    log_detail "Checking for new commits..."
    local commit_count
    commit_count=$(git -C "$APP_DIR" rev-list HEAD.."$remote_branch" --count 2>/dev/null || echo "0")
    log_detail "New commits to pull: $commit_count"

    if [[ "$commit_count" -eq 0 ]]; then
        log_ok "Already up to date, no changes to deploy"
        # Show diff anyway for verbose
        if [[ "$VERBOSE" == true ]]; then
            log_detail "Showing recent commits:"
            git -C "$APP_DIR" log --oneline -5 2>/dev/null | while read -r line; do
                log_detail "  $line"
            done
        fi
    else
        log_detail "New commits:"
        git -C "$APP_DIR" log --oneline HEAD.."$remote_branch" 2>/dev/null | head -10 | while read -r line; do
            log_detail "  $line"
        done
    fi

    # Detect if migration is needed
    log_detail "Checking for migration-related changes..."
    NEEDS_MIGRATION=false

    local changed_files
    changed_files=$(git -C "$APP_DIR" diff --name-only HEAD.."$remote_branch" 2>/dev/null || echo "")

    # Check various migration indicators
    local migration_patterns=(
        "migrations/"
        "prisma/migrations/"
        "alembic/"
        "knex/"
        "database/migrations/"
    )
    local migration_file_patterns=(
        "*_migration*"
        "*migrate*"
        "schema.prisma"
        "schema.sql"
    )

    for pattern in "${migration_patterns[@]}"; do
        if echo "$changed_files" | grep -q "$pattern"; then
            NEEDS_MIGRATION=true
            log_detail "  Detected migration directory change: $pattern"
            break
        fi
    done

    if [[ "$NEEDS_MIGRATION" == false ]]; then
        for pattern in "${migration_file_patterns[@]}"; do
            if echo "$changed_files" | grep -qF "$pattern"; then
                NEEDS_MIGRATION=true
                log_detail "  Detected migration file change: $pattern"
                break
            fi
        done
    fi

    # Also check for lock file changes (package-lock.json, requirements.txt)
    local deps_changed=false
    if echo "$changed_files" | grep -qE "(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|requirements\.txt|Pipfile\.lock|poetry\.lock|go\.sum|Cargo\.lock)"; then
        deps_changed=true
        log_detail "  Detected dependency changes"
    fi

    if [[ "$NEEDS_MIGRATION" == true ]]; then
        log_warn "Database migration will be required"
    else
        log_detail "No migration changes detected"
    fi

    log_ok "Change check completed ($commit_count new commits)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 2: EXECUTE UPDATE
# ═══════════════════════════════════════════════════════════════════════════════

# ── Step 4: Pull Code ────────────────────────────────────────────────────────
pull_code() {
    CURRENT_STEP="pull_code"
    log_step "Step 4/11: Pulling latest code"

    case "$METHOD" in
        docker|server)
            log_detail "git pull origin $ORIGINAL_BRANCH ..."
            if ! git -C "$APP_DIR" pull origin "$ORIGINAL_BRANCH" 2>&1; then
                log_error "git pull failed"
                return 1
            fi
            log_ok "Code pulled successfully"
            log_detail "New HEAD: $(git -C "$APP_DIR" rev-parse --short HEAD)"
            ;;
        ssh)
            log_detail "Pulling code on remote server..."
            ssh_cmd "cd $REMOTE_DIR && git pull origin $ORIGINAL_BRANCH" 2>&1
            log_ok "Remote code pulled successfully"
            ;;
    esac
}

# ── Step 5: Install Dependencies ─────────────────────────────────────────────
install_deps() {
    CURRENT_STEP="install_deps"
    log_step "Step 5/11: Installing dependencies"

    local project_type
    project_type=$(detect_project_type)

    case "$METHOD" in
        docker|server)
            case "$project_type" in
                node)
                    if [[ -f "$APP_DIR/package.json" ]]; then
                        log_detail "Running npm ci --production ..."
                        if [[ -f "$APP_DIR/package-lock.json" ]]; then
                            npm ci --omit=dev --prefix "$APP_DIR" 2>&1 | while IFS= read -r line; do
                                log_detail "  $line"
                            done
                        else
                            npm install --production --prefix "$APP_DIR" 2>&1 | while IFS= read -r line; do
                                log_detail "  $line"
                            done
                        fi
                        log_ok "Node.js dependencies installed"
                    fi
                    ;;
                python)
                    if [[ -f "$APP_DIR/requirements.txt" ]]; then
                        log_detail "Running pip install -r requirements.txt ..."
                        if [[ -d "$APP_DIR/venv" ]] || [[ -d "$APP_DIR/.venv" ]]; then
                            local venv_dir="$APP_DIR/venv"
                            [[ -d "$APP_DIR/.venv" ]] && venv_dir="$APP_DIR/.venv"
                            "$venv_dir/bin/pip" install -r "$APP_DIR/requirements.txt" --quiet 2>&1 | while IFS= read -r line; do
                                log_detail "  $line"
                            done
                        else
                            pip install -r "$APP_DIR/requirements.txt" --quiet 2>&1 | while IFS= read -r line; do
                                log_detail "  $line"
                            done
                        fi
                        log_ok "Python dependencies installed"
                    fi
                    ;;
                go)
                    if [[ -f "$APP_DIR/go.mod" ]]; then
                        log_detail "Running go mod download ..."
                        (cd "$APP_DIR" && go mod download 2>&1) | while IFS= read -r line; do
                            log_detail "  $line"
                        done
                        log_ok "Go dependencies downloaded"
                    fi
                    ;;
                *)
                    log_warn "Unknown project type, skipping dependency installation"
                    ;;
            esac
            ;;
        ssh)
            log_detail "Installing dependencies on remote server..."
            ssh_cmd "cd $REMOTE_DIR && if [ -f package.json ] && [ -f package-lock.json ]; then npm ci --omit=dev; elif [ -f requirements.txt ]; then pip install -r requirements.txt --quiet; fi" 2>&1
            log_ok "Remote dependencies installed"
            ;;
    esac
}

# ── Step 6: Build ────────────────────────────────────────────────────────────
build() {
    CURRENT_STEP="build"
    log_step "Step 6/11: Building application"

    case "$METHOD" in
        docker|server)
            if [[ -f "$APP_DIR/package.json" ]]; then
                if grep -q '"build"' "$APP_DIR/package.json"; then
                    log_detail "Running npm run build ..."
                    if ! npm run build --prefix "$APP_DIR" 2>&1 | while IFS= read -r line; do
                        log_detail "  $line"
                    done; then
                        log_error "Build failed"
                        return 1
                    fi
                    log_ok "Build completed successfully"
                else
                    log_detail "No build script defined in package.json, skipping"
                fi
            elif [[ -f "$APP_DIR/Makefile" ]]; then
                log_detail "Running make build ..."
                if ! (cd "$APP_DIR" && make build 2>&1 | while IFS= read -r line; do log_detail "  $line"; done); then
                    log_error "Build failed"
                    return 1
                fi
                log_ok "Build completed successfully"
            else
                log_detail "No build command detected, skipping build step"
            fi
            ;;
        ssh)
            log_detail "Building on remote server..."
            ssh_cmd "cd $REMOTE_DIR && if [ -f package.json ] && grep -q '\"build\"' package.json; then npm run build; elif [ -f Makefile ]; then make build; fi" 2>&1
            log_ok "Remote build completed"
            ;;
    esac
}

# ── Step 7: Run Migrations ───────────────────────────────────────────────────
run_migrations() {
    CURRENT_STEP="run_migrations"
    log_step "Step 7/11: Running database migrations"

    if [[ "$SKIP_MIGRATION" == true ]]; then
        log_warn "Migrations skipped (--skip-migration flag set)"
        return 0
    fi

    if [[ "$NEEDS_MIGRATION" == false ]]; then
        log_detail "No migration changes detected, skipping"
        return 0
    fi

    log_detail "Migration changes detected, running migrations..."

    case "$METHOD" in
        docker|server)
            # Prisma
            if [[ -f "$APP_DIR/prisma/schema.prisma" ]] && command -v npx &>/dev/null; then
                log_detail "Running: npx prisma migrate deploy ..."
                if ! (cd "$APP_DIR" && npx prisma migrate deploy 2>&1 | while IFS= read -r line; do log_detail "  $line"; done); then
                    log_error "Prisma migration failed"
                    return 1
                fi
                log_ok "Prisma migrations applied"
                return 0
            fi

            # Django
            if [[ -f "$APP_DIR/manage.py" ]]; then
                local python_cmd="python"
                [[ -d "$APP_DIR/venv" ]] && python_cmd="$APP_DIR/venv/bin/python"
                [[ -d "$APP_DIR/.venv" ]] && python_cmd="$APP_DIR/.venv/bin/python"
                log_detail "Running: $python_cmd manage.py migrate ..."
                if ! (cd "$APP_DIR" && $python_cmd manage.py migrate 2>&1 | while IFS= read -r line; do log_detail "  $line"; done); then
                    log_error "Django migration failed"
                    return 1
                fi
                log_ok "Django migrations applied"
                return 0
            fi

            # Sequelize
            if [[ -f "$APP_DIR/.sequelizerc" ]] && command -v npx &>/dev/null; then
                log_detail "Running: npx sequelize db:migrate ..."
                if ! (cd "$APP_DIR" && npx sequelize db:migrate 2>&1 | while IFS= read -r line; do log_detail "  $line"; done); then
                    log_error "Sequelize migration failed"
                    return 1
                fi
                log_ok "Sequelize migrations applied"
                return 0
            fi

            # Alembic
            if [[ -f "$APP_DIR/alembic.ini" ]]; then
                local python_cmd="python"
                [[ -d "$APP_DIR/venv" ]] && python_cmd="$APP_DIR/venv/bin/python"
                [[ -d "$APP_DIR/.venv" ]] && python_cmd="$APP_DIR/.venv/bin/python"
                log_detail "Running: $python_cmd -m alembic upgrade head ..."
                if ! (cd "$APP_DIR" && $python_cmd -m alembic upgrade head 2>&1 | while IFS= read -r line; do log_detail "  $line"; done); then
                    log_error "Alembic migration failed"
                    return 1
                fi
                log_ok "Alembic migrations applied"
                return 0
            fi

            # Knex
            if [[ -f "$APP_DIR/knexfile.js" ]] || [[ -f "$APP_DIR/knexfile.ts" ]]; then
                log_detail "Running: npx knex migrate:latest ..."
                if ! (cd "$APP_DIR" && npx knex migrate:latest 2>&1 | while IFS= read -r line; do log_detail "  $line"; done); then
                    log_error "Knex migration failed"
                    return 1
                fi
                log_ok "Knex migrations applied"
                return 0
            fi

            # TypeORM
            if grep -q "typeorm" "$APP_DIR/package.json" 2>/dev/null; then
                log_detail "Running: npx typeorm migration:run ..."
                if ! (cd "$APP_DIR" && npx typeorm migration:run -d "$APP_DIR/tsconfig.json" 2>&1 | while IFS= read -r line; do log_detail "  $line"; done); then
                    log_error "TypeORM migration failed"
                    return 1
                fi
                log_ok "TypeORM migrations applied"
                return 0
            fi

            log_warn "No recognized migration tool found, skipping migrations"
            ;;
        ssh)
            log_detail "Running migrations on remote server..."
            ssh_cmd "cd $REMOTE_DIR && \
                if [ -f prisma/schema.prisma ]; then npx prisma migrate deploy; \
                elif [ -f manage.py ]; then python manage.py migrate; \
                elif [ -f .sequelizerc ]; then npx sequelize db:migrate; \
                elif [ -f alembic.ini ]; then python -m alembic upgrade head; \
                elif [ -f knexfile.js ] || [ -f knexfile.ts ]; then npx knex migrate:latest; \
                fi" 2>&1
            log_ok "Remote migrations completed"
            ;;
    esac
}

# ── Step 8: Restart Service ──────────────────────────────────────────────────
restart_service() {
    CURRENT_STEP="restart_service"
    log_step "Step 8/11: Restarting service"

    case "$METHOD" in
        docker)
            local compose_file=""
            for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
                if [[ -f "$APP_DIR/$f" ]]; then
                    compose_file="$APP_DIR/$f"
                    break
                fi
            done

            if [[ -z "$compose_file" ]]; then
                log_error "No docker-compose file found"
                return 1
            fi

            log_detail "Running: docker compose up -d --build ..."
            if ! docker compose -f "$compose_file" up -d --build 2>&1 | while IFS= read -r line; do
                log_detail "  $line"
            done; then
                log_error "Docker compose up failed"
                return 1
            fi
            log_ok "Docker containers restarted"
            ;;
        server)
            log_detail "Running: systemctl restart $SERVICE_NAME ..."
            if ! sudo systemctl restart "$SERVICE_NAME" 2>&1; then
                log_error "Failed to restart service: $SERVICE_NAME"
                return 1
            fi
            log_ok "Service $SERVICE_NAME restarted"
            ;;
        ssh)
            log_detail "Syncing files to remote server..."
            rsync_cmd "$APP_DIR/" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/" \
                --exclude='node_modules' \
                --exclude='.git' \
                --exclude='venv' \
                --exclude='.venv' \
                --exclude='__pycache__' \
                --exclude='.env.local' \
                2>&1 | while IFS= read -r line; do
                log_detail "  $line"
            done

            log_detail "Installing deps and restarting on remote..."
            ssh_cmd "cd $REMOTE_DIR && \
                if [ -f package.json ] && [ -f package-lock.json ]; then npm ci --omit=dev; fi && \
                if [ -f requirements.txt ]; then pip install -r requirements.txt --quiet; fi && \
                sudo systemctl restart ${SERVICE_NAME:-app} 2>/dev/null || \
                (if [ -f docker-compose.yml ] || [ -f compose.yml ]; then docker compose up -d --build; fi) || true" 2>&1
            log_ok "Remote service restarted"
            ;;
    esac
}

# ── Step 9: Wait for Healthy ─────────────────────────────────────────────────
wait_healthy() {
    CURRENT_STEP="wait_healthy"
    log_step "Step 9/11: Waiting for service to become healthy"

    if [[ -z "$HEALTH_URL" ]]; then
        log_detail "No health URL configured, skipping health wait"
        log_ok "Skipping health check (no URL configured)"
        return 0
    fi

    local max_attempts=30
    local interval=2
    local attempt=0

    log_detail "Waiting for $HEALTH_URL (up to $((max_attempts * interval))s) ..."

    while [[ $attempt -lt $max_attempts ]]; do
        attempt=$((attempt + 1))
        local http_code
        http_code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$HEALTH_URL" 2>/dev/null || echo "000")

        if [[ "$http_code" =~ ^2 ]]; then
            log_ok "Service is healthy (HTTP $http_code) after ${attempt} attempts"
            return 0
        fi

        log_detail "  Attempt $attempt/$max_attempts: HTTP $http_code"
        sleep "$interval"
    done

    log_error "Service did not become healthy within $((max_attempts * interval))s"
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 3: POST-DEPLOYMENT
# ═══════════════════════════════════════════════════════════════════════════════

# ── Step 10: Verify ──────────────────────────────────────────────────────────
verify() {
    CURRENT_STEP="verify"
    log_step "Step 10/11: Verifying deployment"

    # Health check
    if [[ -n "$HEALTH_URL" ]]; then
        log_detail "Running health check: $HEALTH_URL"
        local http_code
        http_code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$HEALTH_URL" 2>/dev/null || echo "000")
        if [[ "$http_code" =~ ^2 ]]; then
            log_ok "Health check passed (HTTP $http_code)"
        else
            log_error "Health check failed (HTTP $http_code)"
            return 1
        fi
    fi

    # Check recent logs for errors
    log_detail "Checking recent logs for errors..."
    case "$METHOD" in
        docker)
            local compose_file=""
            for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
                if [[ -f "$APP_DIR/$f" ]]; then
                    compose_file="$APP_DIR/$f"
                    break
                fi
            done
            if [[ -n "$compose_file" ]]; then
                local error_logs
                error_logs=$(docker compose -f "$compose_file" logs --tail=50 --since=2m 2>/dev/null | grep -iE "(error|fatal|panic|exception)" || true)
                if [[ -n "$error_logs" ]]; then
                    log_warn "Found errors in recent Docker logs:"
                    echo "$error_logs" | tail -5 | while read -r line; do
                        log_detail "  $line"
                    done
                else
                    log_ok "No errors in recent Docker logs"
                fi
            fi
            ;;
        server)
            if [[ -n "$SERVICE_NAME" ]]; then
                local error_logs
                error_logs=$(sudo journalctl -u "$SERVICE_NAME" --since "2 minutes ago" --no-pager 2>/dev/null | grep -iE "(error|fatal|panic|exception)" || true)
                if [[ -n "$error_logs" ]]; then
                    log_warn "Found errors in recent service logs:"
                    echo "$error_logs" | tail -5 | while read -r line; do
                        log_detail "  $line"
                    done
                else
                    log_ok "No errors in recent service logs"
                fi
            fi
            ;;
        ssh)
            local error_logs
            error_logs=$(ssh_cmd "sudo journalctl -u ${SERVICE_NAME:-app} --since '2 minutes ago' --no-pager 2>/dev/null | grep -iE '(error|fatal|panic|exception)'" || true)
            if [[ -n "$error_logs" ]]; then
                log_warn "Found errors in remote logs:"
                echo "$error_logs" | tail -5 | while read -r line; do
                    log_detail "  $line"
                done
            else
                log_ok "No errors in remote logs"
            fi
            ;;
    esac

    log_ok "Deployment verification completed"
}

# ── Step 11: Cleanup ─────────────────────────────────────────────────────────
cleanup() {
    CURRENT_STEP="cleanup"
    log_step "Step 11/11: Cleanup"

    case "$METHOD" in
        docker)
            log_detail "Pruning unused Docker images..."
            docker image prune -f >/dev/null 2>&1 || true
            log_detail "Pruning Docker build cache..."
            docker builder prune -f >/dev/null 2>&1 || true
            log_ok "Docker cleanup completed"
            ;;
        server)
            # Remove old backups (keep last 3)
            log_detail "Removing old backups (keeping last 3)..."
            local backup_count
            backup_count=$(ls -1d "$BACKUP_DIR"/app_backup_*.tar.gz 2>/dev/null | wc -l || echo "0")
            if [[ "$backup_count" -gt 3 ]]; then
                ls -1t "$BACKUP_DIR"/app_backup_*.tar.gz 2>/dev/null | tail -n +4 | while read -r old_backup; do
                    log_detail "  Removing: $old_backup"
                    rm -f "$old_backup"
                done
                log_ok "Removed $((backup_count - 3)) old backups"
            else
                log_detail "No old backups to remove ($backup_count current)"
            fi

            # Clean build temp files
            log_detail "Cleaning build temp files..."
            rm -rf "$APP_DIR/tmp" "$APP_DIR/.cache" 2>/dev/null || true
            find "$APP_DIR" -name "*.tmp" -delete 2>/dev/null || true

            # Vacuum journal logs
            log_detail "Vacuuming journal logs (max 100MB)..."
            sudo journalctl --vacuum-size=100M >/dev/null 2>&1 || true
            log_ok "Server cleanup completed"
            ;;
        ssh)
            log_detail "Cleaning up on remote server..."
            ssh_cmd "cd $(dirname $REMOTE_DIR) && \
                backup_count=\$(ls -1d *_backup_*.tar.gz 2>/dev/null | wc -l); \
                if [ \$backup_count -gt 3 ]; then \
                    ls -1t *_backup_*.tar.gz 2>/dev/null | tail -n +4 | xargs rm -f; \
                fi && \
                sudo journalctl --vacuum-size=100M >/dev/null 2>&1 || true" 2>/dev/null || true
            log_ok "Remote cleanup completed"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# ROLLBACK
# ═══════════════════════════════════════════════════════════════════════════════

rollback() {
    log_phase "ROLLBACK: Deployment failed at '$CURRENT_STEP', initiating rollback..."

    if [[ -z "$BACKUP_PATH" ]]; then
        log_error "No backup available for rollback!"
        log_error "Manual intervention required"
        return 1
    fi

    local rollback_success=true

    case "$METHOD" in
        docker)
            rollback_docker || rollback_success=false
            ;;
        server)
            rollback_server || rollback_success=false
            ;;
        ssh)
            rollback_ssh || rollback_success=false
            ;;
    esac

    if [[ "$rollback_success" == true ]]; then
        log_ok "Rollback completed successfully"
        # Verify after rollback
        if [[ -n "$HEALTH_URL" ]]; then
            sleep 5
            local http_code
            http_code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$HEALTH_URL" 2>/dev/null || echo "000")
            if [[ "$http_code" =~ ^2 ]]; then
                log_ok "Service is healthy after rollback (HTTP $http_code)"
            else
                log_error "Service is NOT healthy after rollback (HTTP $http_code)"
                log_error "Manual intervention required!"
            fi
        fi
    else
        log_error "Rollback FAILED!"
        log_error "Manual intervention required!"
    fi

    return $([[ "$rollback_success" == true ]] && echo 0 || echo 1)
}

rollback_docker() {
    log_detail "Rolling back Docker deployment..."

    local compose_file=""
    for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        if [[ -f "$APP_DIR/$f" ]]; then
            compose_file="$APP_DIR/$f"
            break
        fi
    done

    if [[ -z "$compose_file" ]]; then
        log_error "No docker-compose file found for rollback"
        return 1
    fi

    # Reset to previous commit
    log_detail "Resetting git to previous state..."
    git -C "$APP_DIR" reset --hard HEAD@{1} 2>/dev/null || {
        log_error "Failed to reset git"
        return 1
    }

    # Restore image
    if [[ -f "$BACKUP_PATH" ]]; then
        log_detail "Loading Docker image from backup: $BACKUP_PATH"
        docker load -i "$BACKUP_PATH" 2>/dev/null || true
    fi

    # Restart with previous version
    log_detail "Restarting Docker containers with previous version..."
    docker compose -f "$compose_file" up -d 2>&1 || {
        log_error "Failed to restart containers"
        return 1
    }

    log_ok "Docker rollback completed"
    return 0
}

rollback_server() {
    log_detail "Rolling back server deployment..."

    # Reset to previous commit
    log_detail "Resetting git to previous state..."
    git -C "$APP_DIR" reset --hard HEAD@{1} 2>/dev/null || {
        log_error "Failed to reset git"
        return 1
    }

    # Restore from backup tar
    if [[ -f "$BACKUP_PATH" ]]; then
        log_detail "Restoring files from backup: $BACKUP_PATH"
        tar -xzf "$BACKUP_PATH" -C "$(dirname "$APP_DIR")" 2>/dev/null || {
            log_error "Failed to restore from backup"
            return 1
        }
    fi

    # Reinstall deps
    local project_type
    project_type=$(detect_project_type)
    case "$project_type" in
        node)
            [[ -f "$APP_DIR/package-lock.json" ]] && npm ci --omit=dev --prefix "$APP_DIR" 2>/dev/null || true
            ;;
        python)
            [[ -f "$APP_DIR/requirements.txt" ]] && pip install -r "$APP_DIR/requirements.txt" --quiet 2>/dev/null || true
            ;;
    esac

    # Restart service
    if [[ -n "$SERVICE_NAME" ]]; then
        log_detail "Restarting service: $SERVICE_NAME"
        sudo systemctl restart "$SERVICE_NAME" 2>/dev/null || {
            log_error "Failed to restart service"
            return 1
        }
    fi

    log_ok "Server rollback completed"
    return 0
}

rollback_ssh() {
    log_detail "Rolling back SSH deployment..."

    # Reset local git
    log_detail "Resetting local git to previous state..."
    git -C "$APP_DIR" reset --hard HEAD@{1} 2>/dev/null || true

    # Restore on remote
    log_detail "Restoring remote from backup..."
    ssh_cmd "cd $(dirname $REMOTE_DIR) && \
        if [ -f $BACKUP_PATH ]; then \
            tar -xzf $BACKUP_PATH -C $(dirname $REMOTE_DIR) && \
            cd $REMOTE_DIR && \
            if [ -f package-lock.json ]; then npm ci --omit=dev; fi && \
            if [ -f requirements.txt ]; then pip install -r requirements.txt --quiet; fi && \
            sudo systemctl restart ${SERVICE_NAME:-app} 2>/dev/null || \
            (if [ -f docker-compose.yml ] || [ -f compose.yml ]; then docker compose up -d; fi) || true; \
        else \
            echo 'No remote backup found'; \
            exit 1; \
        fi" 2>&1 || {
        log_error "Remote rollback failed"
        return 1
    }

    log_ok "SSH rollback completed"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

print_summary() {
    local exit_code=$1
    local end_time
    end_time=$(date +%s)
    local duration=$(( end_time - DEPLOY_START_TIME ))
    local minutes=$(( duration / 60 ))
    local seconds=$(( duration % 60 ))

    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  DEPLOYMENT SUMMARY${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "  Method:          $METHOD"
    echo -e "  App Directory:   $APP_DIR"
    echo -e "  Branch:          $ORIGINAL_BRANCH"
    echo -e "  Duration:        ${minutes}m ${seconds}s"
    echo -e "  Backup:          $([ "$SKIP_BACKUP" == true ] && echo "SKIPPED" || echo "$BACKUP_PATH")"

    if [[ $exit_code -eq 0 ]]; then
        if [[ -n "$HEALTH_URL" ]]; then
            local http_code
            http_code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$HEALTH_URL" 2>/dev/null || echo "000")
            echo -e "  Health Status:   ${GREEN}HTTP $http_code${NC}"
        else
            echo -e "  Health Status:   ${YELLOW}Not configured${NC}"
        fi
        echo -e "  Result:          ${GREEN}SUCCESS${NC}"
    else
        echo -e "  Result:          ${RED}FAILED${NC}"
        echo -e "  Failed Step:    $CURRENT_STEP"
    fi
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
    echo ""

    return $exit_code
}

main() {
    parse_args "$@"
    validate_args

    DEPLOY_START_TIME=$(date +%s)

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          Automated Deployment - $(date '+%Y-%m-%d %H:%M:%S')          ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "  Method: $METHOD  |  App: $APP_DIR  |  Branch: $(detect_current_branch)"
    echo ""

    # ── Phase 1: Pre-deployment ───────────────────────────────────────────────
    log_phase "PHASE 1: Pre-deployment"
    pre_check
    backup
    check_changes

    # ── Phase 2: Execute update (with rollback on failure) ────────────────────
    log_phase "PHASE 2: Execute update"

    DEPLOY_PHASE="execute"

    if ! pull_code; then
        rollback
        print_summary 1
        exit 1
    fi

    if ! install_deps; then
        rollback
        print_summary 1
        exit 1
    fi

    if ! build; then
        rollback
        print_summary 1
        exit 1
    fi

    if ! run_migrations; then
        rollback
        print_summary 1
        exit 1
    fi

    if ! restart_service; then
        rollback
        print_summary 1
        exit 1
    fi

    if ! wait_healthy; then
        log_error "Service did not become healthy after restart"
        rollback
        print_summary 1
        exit 1
    fi

    # ── Phase 3: Post-deployment ──────────────────────────────────────────────
    log_phase "PHASE 3: Post-deployment"

    DEPLOY_PHASE="post"

    if ! verify; then
        log_warn "Verification found issues, but deployment may still be functional"
        # Don't rollback on verification warnings - just report
    fi

    cleanup

    # ── Done ──────────────────────────────────────────────────────────────────
    print_summary 0
}

main "$@"
