#!/bin/bash
set -euo pipefail

# ============================================================
# generate-docker-compose.sh
# 根据项目类型生成 docker-compose.yml 和 .env.docker
# 用法: bash generate-docker-compose.sh --type <fullstack|cms> [选项...]
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/../templates"

# ---- 默认值 ----
TYPE=""
APP_PORT="3000"
DB_TYPE="postgresql"
DB_PORT=""
USE_REDIS="false"
APP_NAME="myapp"
APP_DIR="."
INTERNAL_PORT="3000"

# ---- 颜色输出 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
用法: bash generate-docker-compose.sh --type <fullstack|cms> [选项]

必需参数:
  --type <type>             部署类型: fullstack, cms

可选参数:
  --app-port <port>         应用对外端口 (默认: 3000)
  --db-type <type>          数据库类型: postgresql, mysql, mongodb, none (默认: postgresql)
  --db-port <port>          数据库对外端口 (默认: 根据数据库类型自动选择)
  --use-redis <bool>        是否启用 Redis: true, false (默认: false)
  --app-name <name>         应用名称 (默认: myapp)
  --app-dir <path>          目标项目目录 (默认: 当前目录)
  -h, --help                显示帮助信息
EOF
    exit 0
}

error_exit() {
    echo -e "${RED}错误: $1${NC}" >&2
    exit 1
}

# ---- 参数解析 ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --type)
            TYPE="$2"
            shift 2
            ;;
        --app-port)
            APP_PORT="$2"
            shift 2
            ;;
        --db-type)
            DB_TYPE="$2"
            shift 2
            ;;
        --db-port)
            DB_PORT="$2"
            shift 2
            ;;
        --use-redis)
            USE_REDIS="$2"
            shift 2
            ;;
        --app-name)
            APP_NAME="$2"
            shift 2
            ;;
        --app-dir)
            APP_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            error_exit "未知参数: $1"
            ;;
    esac
done

# ---- 参数校验 ----
if [[ -z "$TYPE" ]]; then
    error_exit "缺少必需参数 --type"
fi

case "$TYPE" in
    fullstack|cms)
        ;;
    *)
        error_exit "不支持的类型: $TYPE (可选: fullstack, cms)"
        ;;
esac

# 验证端口号
if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]]; then
    error_exit "--app-port 必须是数字: $APP_PORT"
fi

# 验证数据库类型
case "$DB_TYPE" in
    postgresql|mysql|mongodb|none)
        ;;
    *)
        error_exit "不支持的数据库类型: $DB_TYPE (可选: postgresql, mysql, mongodb, none)"
        ;;
esac

# 验证 Redis 开关
case "$USE_REDIS" in
    true|false)
        ;;
    *)
        error_exit "--use-redis 必须是 true 或 false: $USE_REDIS"
        ;;
esac

# ---- 数据库类型映射 ----
DB_IMAGE=""
case "$DB_TYPE" in
    postgresql)
        DB_IMAGE="postgres:16-alpine"
        DB_PORT="${DB_PORT:-5432}"
        ;;
    mysql)
        DB_IMAGE="mysql:8.0"
        DB_PORT="${DB_PORT:-3306}"
        ;;
    mongodb)
        DB_IMAGE="mongo:7"
        DB_PORT="${DB_PORT:-27017}"
        ;;
    none)
        DB_IMAGE=""
        DB_PORT="${DB_PORT:-0}"
        ;;
esac

if [[ -n "$DB_PORT" ]] && ! [[ "$DB_PORT" =~ ^[0-9]+$ ]]; then
    error_exit "--db-port 必须是数字: $DB_PORT"
fi

# ---- 确定模板文件 ----
TEMPLATE_FILE="${TEMPLATE_DIR}/docker-compose.${TYPE}"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    error_exit "模板文件不存在: $TEMPLATE_FILE"
fi

# ---- 确保目标目录存在 ----
if [[ "$APP_DIR" != "." ]]; then
    mkdir -p "$APP_DIR"
fi

# ---- 读取模板并替换占位符 ----
TEMPLATE_CONTENT=$(cat "$TEMPLATE_FILE")

GENERATED_CONTENT="$TEMPLATE_CONTENT"
GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed "s|{{APP_PORT}}|${APP_PORT}|g")
GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed "s|{{DB_TYPE}}|${DB_TYPE}|g")
GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed "s|{{DB_PORT}}|${DB_PORT}|g")
GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed "s|{{USE_REDIS}}|${USE_REDIS}|g")
GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed "s|{{APP_NAME}}|${APP_NAME}|g")
GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed "s|{{INTERNAL_PORT}}|${INTERNAL_PORT}|g")

# 如果数据库类型为 none，移除数据库相关服务定义
if [[ "$DB_TYPE" == "none" ]]; then
    # 移除 db 服务块（从 "  db:" 到下一个顶级服务或文件末尾）
    GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed '/^  db:/,/^  [a-z]/{
        /^  [a-z]/!d
        /^  db:/d
    }')
    # 清理可能残留的空行
    GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed '/^$/N;/^\n$/d')
fi

# 如果不使用 Redis，移除 Redis 相关服务定义
if [[ "$USE_REDIS" == "false" ]]; then
    GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed '/^  redis:/,/^  [a-z]/{
        /^  [a-z]/!d
        /^  redis:/d
    }')
    GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed '/^$/N;/^\n$/d')
fi

# ---- 写入 docker-compose.yml ----
COMPOSE_PATH="${APP_DIR}/docker-compose.yml"
echo "$GENERATED_CONTENT" > "$COMPOSE_PATH"

# ---- 生成 .env.docker 模板 ----
ENV_DOCKER_PATH="${APP_DIR}/.env.docker"

cat > "$ENV_DOCKER_PATH" << 'ENV_DOCKER_EOF'
# ============================================================
# Docker 环境变量配置
# 复制此文件为 .env.docker 并填入实际值
# ============================================================

# 应用配置
APP_NAME=${APP_NAME}
APP_PORT=${APP_PORT}
INTERNAL_PORT=${INTERNAL_PORT}

# 数据库配置
ENV_DOCKER_EOF

case "$DB_TYPE" in
    postgresql)
        cat >> "$ENV_DOCKER_PATH" <<'PG_EOF'
DB_TYPE=postgresql
DB_HOST=db
DB_PORT=5432
DB_NAME=myapp_db
DB_USER=postgres
DB_PASSWORD=changeme_please
DB_CONNECTION_STRING=postgresql://postgres:changeme_please@db:5432/myapp_db
PG_EOF
        ;;
    mysql)
        cat >> "$ENV_DOCKER_PATH" <<'MYSQL_EOF'
DB_TYPE=mysql
DB_HOST=db
DB_PORT=3306
DB_NAME=myapp_db
DB_USER=root
DB_PASSWORD=changeme_please
DB_CONNECTION_STRING=mysql://root:changeme_please@db:3306/myapp_db
MYSQL_EOF
        ;;
    mongodb)
        cat >> "$ENV_DOCKER_PATH" <<'MONGO_EOF'
DB_TYPE=mongodb
DB_HOST=db
DB_PORT=27017
DB_NAME=myapp_db
DB_USER=root
DB_PASSWORD=changeme_please
DB_CONNECTION_STRING=mongodb://root:changeme_please@db:27017/myapp_db
MONGO_EOF
        ;;
    none)
        cat >> "$ENV_DOCKER_PATH" <<'NONE_EOF'
DB_TYPE=none
NONE_EOF
        ;;
esac

if [[ "$USE_REDIS" == "true" ]]; then
    cat >> "$ENV_DOCKER_PATH" <<'REDIS_EOF'

# Redis 配置
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=changeme_please
REDIS_URL=redis://:changeme_please@redis:6379
REDIS_EOF
fi

# ---- 输出结果 ----
echo -e "${GREEN}docker-compose 配置生成成功!${NC}"
echo ""
echo "  docker-compose.yml:  ${COMPOSE_PATH}"
echo "  .env.docker:         ${ENV_DOCKER_PATH}"
echo ""
echo "  类型:                ${TYPE}"
echo "  应用名称:            ${APP_NAME}"
echo "  应用端口:            ${APP_PORT}"
echo "  内部端口:            ${INTERNAL_PORT}"
echo "  数据库类型:          ${DB_TYPE}"
if [[ "$DB_TYPE" != "none" ]]; then
    echo "  数据库镜像:          ${DB_IMAGE}"
    echo "  数据库端口:          ${DB_PORT}"
fi
echo "  Redis:               ${USE_REDIS}"
echo ""
echo -e "${YELLOW}提示:${NC}"
echo "  1. 请编辑 .env.docker 文件，将占位值替换为实际的凭据"
echo "  2. 运行 'docker compose up -d' 启动服务"
echo "  3. 运行 'docker compose down' 停止服务"
