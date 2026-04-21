#!/bin/bash
set -euo pipefail

# ============================================================
# generate-dockerfile.sh
# 根据项目类型生成 Dockerfile
# 用法: bash generate-dockerfile.sh --type <nodejs|python|php|static> --port <port> [选项...]
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/../templates"

# ---- 默认值 ----
TYPE=""
PORT=""
BUILD_CMD=""
START_CMD=""
PACKAGE_MANAGER="npm"
OUTPUT_DIR="dist"
APP_DIR="."

# ---- 颜色输出 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
用法: bash generate-dockerfile.sh --type <nodejs|python|php|static> --port <port> [选项]

必需参数:
  --type <type>             项目类型: nodejs, python, php, static
  --port <port>             应用监听端口

可选参数:
  --build-cmd "cmd"         构建命令 (例如 "npm run build")
  --start-cmd "cmd"         启动命令 (例如 "npm run start")
  --package-manager <pm>    包管理器: npm, yarn, pnpm (默认: npm)
  --output-dir <dir>        构建输出目录 (默认: dist)
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
        --port)
            PORT="$2"
            shift 2
            ;;
        --build-cmd)
            BUILD_CMD="$2"
            shift 2
            ;;
        --start-cmd)
            START_CMD="$2"
            shift 2
            ;;
        --package-manager)
            PACKAGE_MANAGER="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
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

if [[ -z "$PORT" ]]; then
    error_exit "缺少必需参数 --port"
fi

# 验证端口号为数字
if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
    error_exit "--port 必须是数字: $PORT"
fi

# 验证类型
case "$TYPE" in
    nodejs|python|php|static)
        ;;
    *)
        error_exit "不支持的类型: $TYPE (可选: nodejs, python, php, static)"
        ;;
esac

# 验证包管理器
case "$PACKAGE_MANAGER" in
    npm|yarn|pnpm)
        ;;
    *)
        error_exit "不支持的包管理器: $PACKAGE_MANAGER (可选: npm, yarn, pnpm)"
        ;;
esac

# ---- 确定模板文件 ----
# Map type to actual template filename
case "$TYPE" in
    nodejs) TEMPLATE_FILE="${TEMPLATE_DIR}/Dockerfile.node" ;;
    python) TEMPLATE_FILE="${TEMPLATE_DIR}/Dockerfile.python" ;;
    php)    TEMPLATE_FILE="${TEMPLATE_DIR}/Dockerfile.php" ;;
    static) TEMPLATE_FILE="${TEMPLATE_DIR}/Dockerfile.static" ;;
    *)      TEMPLATE_FILE="${TEMPLATE_DIR}/Dockerfile.${TYPE}" ;;
esac

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    error_exit "模板文件不存在: $TEMPLATE_FILE"
fi

# ---- 确保目标目录存在 ----
if [[ "$APP_DIR" != "." ]]; then
    mkdir -p "$APP_DIR"
fi

# 读取模板内容
TEMPLATE_CONTENT=$(cat "$TEMPLATE_FILE")

# ---- 替换占位符 ----
GENERATED_CONTENT="$TEMPLATE_CONTENT"
GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed "s|{{PORT}}|${PORT}|g")
GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed "s|{{BUILD_COMMAND}}|${BUILD_CMD}|g")
GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed "s|{{START_COMMAND}}|${START_CMD}|g")
GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed "s|{{PACKAGE_MANAGER}}|${PACKAGE_MANAGER}|g")
GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed "s|{{OUTPUT_DIR}}|${OUTPUT_DIR}|g")
GENERATED_CONTENT=$(echo "$GENERATED_CONTENT" | sed "s|{{APP_DIR}}|${APP_DIR}|g")

# ---- 写入 Dockerfile ----
DOCKERFILE_PATH="${APP_DIR}/Dockerfile"
echo "$GENERATED_CONTENT" > "$DOCKERFILE_PATH"

# ---- 生成 .dockerignore ----
DOCKERIGNORE_PATH="${APP_DIR}/.dockerignore"
cat > "$DOCKERIGNORE_PATH" <<'DOCKERIGNORE_EOF'
# 依赖目录
node_modules/
vendor/
__pycache__/
*.pyc
.venv/
venv/

# 版本控制
.git/
.gitignore

# IDE 配置
.vscode/
.idea/
*.swp
*.swo

# 操作系统文件
.DS_Store
Thumbs.db

# 环境文件
.env
.env.local
.env.*.local

# 日志
*.log
npm-debug.log*

# 构建产物（由 Dockerfile 内部构建，不需要从宿主机复制）
dist/
build/
.next/
.nuxt/
DOCKERIGNORE_EOF

# ---- 输出结果 ----
echo -e "${GREEN}Dockerfile 生成成功!${NC}"
echo ""
echo "  Dockerfile:     ${DOCKERFILE_PATH}"
echo "  .dockerignore:  ${DOCKERIGNORE_PATH}"
echo ""
echo "  类型:           ${TYPE}"
echo "  端口:           ${PORT}"
echo "  包管理器:       ${PACKAGE_MANAGER}"
if [[ -n "$BUILD_CMD" ]]; then
    echo "  构建命令:       ${BUILD_CMD}"
fi
if [[ -n "$START_CMD" ]]; then
    echo "  启动命令:       ${START_CMD}"
fi
echo "  输出目录:       ${OUTPUT_DIR}"
echo ""
echo -e "${YELLOW}提示: 请检查生成的文件并根据项目需求进行调整。${NC}"
