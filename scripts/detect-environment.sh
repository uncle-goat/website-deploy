#!/bin/bash
# =============================================================================
# Server Environment Detection Script
# Outputs structured JSON describing the current server environment.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Helper: detect whether a command exists
# ---------------------------------------------------------------------------
has_cmd() {
    command -v "$1" &>/dev/null
}

# ---------------------------------------------------------------------------
# Helper: run a command, capture stdout+stderr, return 0 even on failure
# ---------------------------------------------------------------------------
safe_run() {
    "$@" 2>&1 || true
}

# ---------------------------------------------------------------------------
# Helper: extract a version string from typical "tool --version" output
#   e.g. "nginx version: nginx/1.18.0" -> "1.18.0"
# ---------------------------------------------------------------------------
extract_version() {
    # Try to pull the first thing that looks like a version number
    grep -oP '[0-9]+\.[0-9]+(\.[0-9]+)?(\.[0-9]+)?' | head -1 || true
}

# ---------------------------------------------------------------------------
# Helper: check if a TCP port is in LISTEN state
# ---------------------------------------------------------------------------
port_in_use() {
    local port="$1"
    if has_cmd ss; then
        ss -tln 2>/dev/null | grep -q ":${port}\b" && echo true || echo false
    elif has_cmd netstat; then
        netstat -tln 2>/dev/null | grep -q ":${port}\b" && echo true || echo false
    else
        # Fallback: try to connect with a 1-second timeout
        (echo >/dev/tcp/127.0.0.1/"${port}") &>/dev/null && echo true || echo false
    fi
}

# ---------------------------------------------------------------------------
# Helper: check if a port is open in the firewall
# ---------------------------------------------------------------------------
firewall_open_ports() {
    local fw_type="$1"
    local ports=""

    if [[ "$fw_type" == "ufw" ]]; then
        if has_cmd ufw; then
            ports=$(safe_run ufw status | grep -oP '\d+(?=/tcp|\b)' | sort -un | tr '\n' ',' | sed 's/,$//')
        fi
    elif [[ "$fw_type" == "firewalld" ]]; then
        if has_cmd firewall-cmd; then
            ports=$(safe_run firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n' | grep -oP '^\d+' | sort -un | tr '\n' ',' | sed 's/,$//')
        fi
    elif [[ "$fw_type" == "iptables" ]]; then
        if has_cmd iptables; then
            ports=$(safe_run iptables -L INPUT -n 2>/dev/null | grep -oP 'dpt:\K\d+' | sort -un | tr '\n' ',' | sed 's/,$//')
        fi
    fi

    if [[ -z "$ports" ]]; then
        echo "[]"
    else
        # Convert comma-separated to JSON array
        local IFS=','
        local arr=()
        for p in $ports; do
            [[ -n "$p" ]] && arr+=("\"$p\"")
        done
        local joined
        joined=$(IFS=','; echo "${arr[*]}")
        echo "[$joined]"
    fi
}

# ---------------------------------------------------------------------------
# Helper: build a JSON object for ports
# ---------------------------------------------------------------------------
detect_ports() {
    local ports=(80 443 3000 3306 5432 6379 8080 27017)
    local entries=()
    for p in "${ports[@]}"; do
        local in_use
        in_use=$(port_in_use "$p")
        entries+=("\"${p}\":${in_use}")
    done
    local IFS=','
    echo "{${entries[*]}}"
}

# ===========================================================================
# 1. OS Detection
# ===========================================================================
detect_os() {
    local os_name="Unknown" os_version="Unknown" os_id="" os_pretty=""

    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        os_name="${PRETTY_NAME:-$NAME}"
        os_version="${VERSION:-$VERSION_ID}"
        os_id="${ID:-unknown}"
    elif has_cmd lsb_release; then
        os_name=$(safe_run lsb_release -d | sed 's/Description:\s*//')
        os_version=$(safe_run lsb_release -rs)
    elif [[ -f /etc/redhat-release ]]; then
        os_name=$(cat /etc/redhat-release)
    elif [[ -f /etc/debian_version ]]; then
        os_name="Debian"
        os_version=$(cat /etc/debian_version)
    fi

    local arch
    arch=$(uname -m 2>/dev/null || echo "unknown")

    echo "{\"name\":\"${os_name}\",\"version\":\"${os_version}\",\"id\":\"${os_id}\",\"arch\":\"${arch}\"}"
}

# ===========================================================================
# 2. Resources
# ===========================================================================
detect_resources() {
    local cpu_cores mem_mb disk_free_gb

    # CPU cores
    if [[ -f /proc/cpuinfo ]]; then
        cpu_cores=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "1")
    elif has_cmd nproc; then
        cpu_cores=$(nproc 2>/dev/null || echo "1")
    else
        cpu_cores="1"
    fi

    # Memory in MB
    if [[ -f /proc/meminfo ]]; then
        mem_kb=$(grep '^MemTotal:' /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
        mem_mb=$(( mem_kb / 1024 ))
    elif has_cmd free; then
        mem_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
    else
        mem_mb="0"
    fi

    # Disk free in GB (root filesystem)
    if has_cmd df; then
        disk_free_gb=$(df -BG / 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
    else
        disk_free_gb="0"
    fi

    echo "{\"cpu_cores\":${cpu_cores},\"memory_mb\":${mem_mb},\"disk_free_gb\":${disk_free_gb}}"
}

# ===========================================================================
# 3. Docker
# ===========================================================================
detect_docker() {
    local installed=false version="" compose_version="" daemon_running=false

    if has_cmd docker; then
        installed=true
        version=$(safe_run docker --version | extract_version)

        # Docker Compose - try both v1 (docker-compose) and v2 (docker compose)
        if has_cmd docker-compose; then
            compose_version=$(safe_run docker-compose --version | extract_version)
        elif docker compose version &>/dev/null; then
            compose_version=$(safe_run docker compose version | extract_version)
        fi

        # Check if daemon is running
        if docker info &>/dev/null; then
            daemon_running=true
        fi
    fi

    echo "{\"installed\":${installed},\"version\":\"${version}\",\"compose_version\":\"${compose_version}\",\"daemon_running\":${daemon_running}}"
}

# ===========================================================================
# 4. Nginx
# ===========================================================================
detect_nginx() {
    local installed=false version=""

    if has_cmd nginx; then
        installed=true
        # nginx -v outputs to stderr
        version=$(safe_run nginx -v 2>&1 | extract_version)
    fi

    echo "{\"installed\":${installed},\"version\":\"${version}\"}"
}

# ===========================================================================
# 5. Node.js
# ===========================================================================
detect_nodejs() {
    local installed=false version="" pkg_manager="none"

    if has_cmd node; then
        installed=true
        version=$(safe_run node --version | sed 's/^v//')

        # Detect package manager
        if has_cmd pnpm; then
            pkg_manager="pnpm"
        elif has_cmd yarn; then
            pkg_manager="yarn"
        elif has_cmd npm; then
            pkg_manager="npm"
        fi
    fi

    echo "{\"installed\":${installed},\"version\":\"${version}\",\"package_manager\":\"${pkg_manager}\"}"
}

# ===========================================================================
# 6. Python
# ===========================================================================
detect_python() {
    local installed=false version="" venv_available=false

    if has_cmd python3; then
        installed=true
        version=$(safe_run python3 --version | extract_version)
        # Check for venv module
        if python3 -c "import venv" &>/dev/null; then
            venv_available=true
        fi
    elif has_cmd python; then
        installed=true
        version=$(safe_run python --version | extract_version)
        if python -c "import venv" &>/dev/null; then
            venv_available=true
        fi
    fi

    echo "{\"installed\":${installed},\"version\":\"${version}\",\"venv_available\":${venv_available}}"
}

# ===========================================================================
# 7. PHP
# ===========================================================================
detect_php() {
    local installed=false version=""

    if has_cmd php; then
        installed=true
        # php -v outputs to stderr on some systems
        version=$(safe_run php -v | extract_version)
    fi

    echo "{\"installed\":${installed},\"version\":\"${version}\"}"
}

# ===========================================================================
# 8. Go
# ===========================================================================
detect_go() {
    local installed=false version=""

    if has_cmd go; then
        installed=true
        version=$(safe_run go version | extract_version)
    fi

    echo "{\"installed\":${installed},\"version\":\"${version}\"}"
}

# ===========================================================================
# 9. Java
# ===========================================================================
detect_java() {
    local installed=false version=""

    if has_cmd java; then
        installed=true
        version=$(safe_run java -version 2>&1 | extract_version)
    fi

    echo "{\"installed\":${installed},\"version\":\"${version}\"}"
}

# ===========================================================================
# 10. SSH
# ===========================================================================
detect_ssh() {
    local configured=false
    local key_files="[]"

    if has_cmd sshd || [[ -d /etc/ssh ]]; then
        configured=true

        # Collect SSH key file paths
        local keys=()
        for f in /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub; do
            if [[ -f "$f" ]]; then
                keys+=("\"$f\"")
            fi
        done

        if [[ ${#keys[@]} -gt 0 ]]; then
            local IFS=','
            key_files="[$(echo "${keys[*]}")]"
        fi
    fi

    echo "{\"configured\":${configured},\"key_files\":${key_files}}"
}

# ===========================================================================
# 11. Firewall
# ===========================================================================
detect_firewall() {
    local fw_type="none" fw_status="unknown" open_ports="[]"

    if has_cmd ufw && ufw status &>/dev/null; then
        fw_type="ufw"
        local ufw_status
        ufw_status=$(safe_run ufw status | head -1)
        if echo "$ufw_status" | grep -qi "active"; then
            fw_status="active"
        else
            fw_status="inactive"
        fi
        open_ports=$(firewall_open_ports "ufw")
    elif has_cmd firewall-cmd && firewall-cmd --state &>/dev/null; then
        fw_type="firewalld"
        fw_status=$(safe_run firewall-cmd --state)
        open_ports=$(firewall_open_ports "firewalld")
    elif has_cmd iptables && iptables -L INPUT -n &>/dev/null; then
        fw_type="iptables"
        fw_status="active"
        open_ports=$(firewall_open_ports "iptables")
    fi

    echo "{\"type\":\"${fw_type}\",\"status\":\"${fw_status}\",\"open_ports\":${open_ports}}"
}

# ===========================================================================
# 12. Container Detection
# ===========================================================================
detect_container() {
    local in_container=false

    if [[ -f /.dockerenv ]]; then
        in_container=true
    fi

    # Also check cgroup for container indicators
    if [[ -f /proc/1/cgroup ]]; then
        if grep -qa 'docker\|lxc\|containerd\|kubepods' /proc/1/cgroup 2>/dev/null; then
            in_container=true
        fi
    fi

    echo "${in_container}"
}

# ===========================================================================
# 13. User & Sudo
# ===========================================================================
detect_user() {
    local current_user
    current_user=$(whoami 2>/dev/null || echo "unknown")
    local has_sudo=false

    if has_cmd sudo; then
        # Non-interactive sudo check (does not prompt for password)
        if sudo -n true 2>/dev/null; then
            has_sudo=true
        fi
    fi

    echo "{\"user\":\"${current_user}\",\"has_sudo\":${has_sudo}}"
}

# ===========================================================================
# Main - Assemble and Output JSON
# ===========================================================================
main() {
    local os resources docker nginx nodejs python php go java ports ssh firewall in_container user

    os=$(detect_os)
    resources=$(detect_resources)
    docker=$(detect_docker)
    nginx=$(detect_nginx)
    nodejs=$(detect_nodejs)
    python=$(detect_python)
    php=$(detect_php)
    go=$(detect_go)
    java=$(detect_java)
    ports=$(detect_ports)
    ssh=$(detect_ssh)
    firewall=$(detect_firewall)
    in_container=$(detect_container)
    user=$(detect_user)

    # Assemble the full JSON
    local json
    json="{"
    json+="\"os\":${os},"
    json+="\"resources\":${resources},"
    json+="\"docker\":${docker},"
    json+="\"nginx\":${nginx},"
    json+="\"nodejs\":${nodejs},"
    json+="\"python\":${python},"
    json+="\"php\":${php},"
    json+="\"go\":${go},"
    json+="\"java\":${java},"
    json+="\"ports\":${ports},"
    json+="\"ssh\":${ssh},"
    json+="\"firewall\":${firewall},"
    json+="\"in_container\":${in_container},"
    json+="\"user\":${user}"
    json+="}"

    # Pretty-print with jq if available, otherwise output raw JSON
    if has_cmd jq; then
        echo "$json" | jq .
    else
        printf '%s\n' "$json"
    fi
}

main
