#!/bin/bash
# install-dependencies.sh - 自动检测并安装部署所需的依赖工具
# Usage: bash install-dependencies.sh --tool <tool> [--tool <tool>] ... | --all
# Supported tools: docker, nginx, nodejs, python, php, certbot, ufw

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect package manager
detect_pkg_mgr() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v apk &>/dev/null; then
        echo "apk"
    else
        echo "unknown"
    fi
}

# Check if running as root or has sudo
check_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        echo "sudo"
    elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        echo "sudo"
    else
        echo "nosudo"
    fi
}

SUDO_CMD=""
SUDO_CHECK=$(check_sudo)
if [ "$SUDO_CHECK" = "sudo" ] && [ "$(id -u)" -ne 0 ]; then
    SUDO_CMD="sudo"
fi

PKG_MGR=$(detect_pkg_mgr)

# --- Tool installation functions ---

install_docker() {
    if command -v docker &>/dev/null; then
        log_info "Docker already installed: $(docker --version 2>/dev/null | head -1)"
        return 0
    fi
    log_info "Installing Docker..."
    if [ "$PKG_MGR" = "apt" ]; then
        $SUDO_CMD apt-get update -qq
        $SUDO_CMD apt-get install -y -qq ca-certificates curl gnupg
        $SUDO_CMD install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO_CMD gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
        $SUDO_CMD chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | $SUDO_CMD tee /etc/apt/sources.list.d/docker.list > /dev/null
        $SUDO_CMD apt-get update -qq
        $SUDO_CMD apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    elif [ "$PKG_MGR" = "yum" ] || [ "$PKG_MGR" = "dnf" ]; then
        $SUDO_CMD yum install -y yum-utils
        $SUDO_CMD yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        $SUDO_CMD ${PKG_MGR} install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    else
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        $SUDO_CMD sh /tmp/get-docker.sh
        rm -f /tmp/get-docker.sh
    fi
    $SUDO_CMD systemctl enable --now docker 2>/dev/null || true
    if [ "$(id -u)" -ne 0 ]; then
        $SUDO_CMD usermod -aG docker "$(whoami)" 2>/dev/null || true
        log_warn "Added $(whoami) to docker group. Log out and back in for changes to take effect."
    fi
    log_info "Docker installed: $(docker --version 2>/dev/null | head -1)"
}

install_nginx() {
    if command -v nginx &>/dev/null; then
        log_info "Nginx already installed: $(nginx -v 2>&1)"
        return 0
    fi
    log_info "Installing Nginx..."
    case "$PKG_MGR" in
        apt)  $SUDO_CMD apt-get update -qq && $SUDO_CMD apt-get install -y -qq nginx ;;
        yum|dnf) $SUDO_CMD ${PKG_MGR} install -y nginx ;;
        apk)  $SUDO_CMD apk add --no-cache nginx ;;
    esac
    $SUDO_CMD systemctl enable nginx 2>/dev/null || true
    log_info "Nginx installed: $(nginx -v 2>&1)"
}

install_nodejs() {
    if command -v node &>/dev/null; then
        log_info "Node.js already installed: $(node --version 2>/dev/null)"
        return 0
    fi
    log_info "Installing Node.js 20.x..."
    if [ "$PKG_MGR" = "apt" ]; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO_CMD bash -
        $SUDO_CMD apt-get install -y -qq nodejs
    elif [ "$PKG_MGR" = "yum" ] || [ "$PKG_MGR" = "dnf" ]; then
        curl -fsSL https://rpm.nodesource.com/setup_20.x | $SUDO_CMD bash -
        $SUDO_CMD ${PKG_MGR} install -y nodejs
    elif [ "$PKG_MGR" = "apk" ]; then
        $SUDO_CMD apk add --no-cache nodejs npm
    fi
    log_info "Node.js installed: $(node --version 2>/dev/null)"
}

install_python() {
    if command -v python3 &>/dev/null; then
        log_info "Python already installed: $(python3 --version 2>/dev/null)"
        return 0
    fi
    log_info "Installing Python 3..."
    case "$PKG_MGR" in
        apt)  $SUDO_CMD apt-get update -qq && $SUDO_CMD apt-get install -y -qq python3 python3-pip python3-venv ;;
        yum|dnf) $SUDO_CMD ${PKG_MGR} install -y python3 python3-pip ;;
        apk)  $SUDO_CMD apk add --no-cache python3 py3-pip ;;
    esac
    log_info "Python installed: $(python3 --version 2>/dev/null)"
}

install_php() {
    if command -v php &>/dev/null; then
        log_info "PHP already installed: $(php --version 2>/dev/null | head -1)"
        return 0
    fi
    log_info "Installing PHP 8.2..."
    if [ "$PKG_MGR" = "apt" ]; then
        $SUDO_CMD apt-get update -qq
        $SUDO_CMD apt-get install -y -qq software-properties-common
        $SUDO_CMD add-apt-repository -y ppa:ondrej/php 2>/dev/null || true
        $SUDO_CMD apt-get update -qq
        $SUDO_CMD apt-get install -y -qq php8.2-fpm php8.2-cli php8.2-common php8.2-mysql php8.2-pgsql php8.2-gd php8.2-zip php8.2-curl php8.2-xml php8.2-mbstring
    elif [ "$PKG_MGR" = "yum" ] || [ "$PKG_MGR" = "dnf" ]; then
        $SUDO_CMD ${PKG_MGR} install -y php php-fpm php-mysqlnd php-pgsql php-gd php-xml php-mbstring
    elif [ "$PKG_MGR" = "apk" ]; then
        $SUDO_CMD apk add --no-cache php82 php82-fpm php82-pdo_mysql php82-pdo_pgsql php82-gd php82-xml
    fi
    log_info "PHP installed: $(php --version 2>/dev/null | head -1)"
}

install_certbot() {
    if command -v certbot &>/dev/null; then
        log_info "Certbot already installed: $(certbot --version 2>/dev/null)"
        return 0
    fi
    log_info "Installing Certbot..."
    case "$PKG_MGR" in
        apt)  $SUDO_CMD apt-get update -qq && $SUDO_CMD apt-get install -y -qq certbot python3-certbot-nginx ;;
        yum|dnf) $SUDO_CMD ${PKG_MGR} install -y certbot python3-certbot-nginx ;;
        apk)  $SUDO_CMD apk add --no-cache certbot ;;
    esac
    log_info "Certbot installed: $(certbot --version 2>/dev/null)"
}

install_ufw() {
    if command -v ufw &>/dev/null; then
        log_info "UFW already installed"
        return 0
    fi
    log_info "Installing UFW..."
    case "$PKG_MGR" in
        apt)  $SUDO_CMD apt-get update -qq && $SUDO_CMD apt-get install -y -qq ufw ;;
        *)    log_warn "UFW is only available on Ubuntu/Debian. Skipping." ; return 0 ;;
    esac
    log_info "UFW installed"
}

# --- Main ---

show_help() {
    echo "Usage: bash install-dependencies.sh --tool <tool> [--tool <tool>] ... | --all"
    echo ""
    echo "Supported tools: docker, nginx, nodejs, python, php, certbot, ufw"
    echo ""
    echo "Examples:"
    echo "  bash install-dependencies.sh --tool docker"
    echo "  bash install-dependencies.sh --tool nginx --tool nodejs --tool certbot"
    echo "  bash install-dependencies.sh --all"
}

TOOLS_TO_INSTALL=()
INSTALL_ALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tool)
            TOOLS_TO_INSTALL+=("$2")
            shift 2
            ;;
        --all)
            INSTALL_ALL=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

if [ "$INSTALL_ALL" = true ]; then
    TOOLS_TO_INSTALL=(docker nginx nodejs python php certbot ufw)
fi

if [ ${#TOOLS_TO_INSTALL[@]} -eq 0 ]; then
    log_error "No tools specified. Use --tool <tool> or --all"
    show_help
    exit 1
fi

log_info "Package manager detected: $PKG_MGR"
log_info "Tools to install: ${TOOLS_TO_INSTALL[*]}"
echo ""

for tool in "${TOOLS_TO_INSTALL[@]}"; do
    case "$tool" in
        docker)   install_docker ;;
        nginx)    install_nginx ;;
        nodejs)   install_nodejs ;;
        python)   install_python ;;
        php)      install_php ;;
        certbot)  install_certbot ;;
        ufw)      install_ufw ;;
        *)        log_error "Unknown tool: $tool" ;;
    esac
done

echo ""
log_info "All requested tools have been processed."
