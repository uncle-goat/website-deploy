#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/../templates/systemd-service.template"
SERVICE_DIR="/etc/systemd/system"

usage() {
    cat <<EOF
Usage: bash generate-systemd-service.sh --name <service-name> --exec <command> [options]

Options:
  --name <service-name>       Service name (required, without .service extension)
  --exec <command>            ExecStart command (required)
  --user <user>               Service user (default: www-data)
  --work-dir <path>           WorkingDirectory (default: /opt/<name>)
  --env-file <path>           Environment file path (default: /etc/default/<name>)
  --description <desc>        Service description (default: <name> service)
  -h, --help                  Show this help message

Examples:
  bash generate-systemd-service.sh --name myapp --exec "/usr/bin/node /opt/myapp/server.js"
  bash generate-systemd-service.sh --name myapp --exec "/usr/bin/python3 app.py" --user ubuntu --work-dir /home/ubuntu/myapp
EOF
    exit "${1:-0}"
}

# Parse arguments
SERVICE_NAME=""
EXEC_COMMAND=""
SERVICE_USER="www-data"
WORK_DIR=""
ENV_FILE=""
DESCRIPTION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            SERVICE_NAME="$2"
            shift 2
            ;;
        --exec)
            EXEC_COMMAND="$2"
            shift 2
            ;;
        --user)
            SERVICE_USER="$2"
            shift 2
            ;;
        --work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        --env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        --description)
            DESCRIPTION="$2"
            shift 2
            ;;
        -h|--help)
            usage 0
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            usage 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SERVICE_NAME" ]]; then
    echo "Error: --name is required" >&2
    usage 1
fi

if [[ -z "$EXEC_COMMAND" ]]; then
    echo "Error: --exec is required" >&2
    usage 1
fi

# Validate service name (no spaces, no special characters)
if [[ ! "$SERVICE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Invalid service name '$SERVICE_NAME'. Use only alphanumeric characters, hyphens, and underscores." >&2
    exit 1
fi

# Set defaults
if [[ -z "$WORK_DIR" ]]; then
    WORK_DIR="/opt/${SERVICE_NAME}"
fi

if [[ -z "$ENV_FILE" ]]; then
    ENV_FILE="/etc/default/${SERVICE_NAME}"
fi

if [[ -z "$DESCRIPTION" ]]; then
    DESCRIPTION="${SERVICE_NAME} service"
fi

# Check template file exists
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "Error: Template file not found: $TEMPLATE_FILE" >&2
    exit 1
fi

# Check if running as root (needed to write to /etc/systemd/system)
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)." >&2
    exit 1
fi

# Read template and replace placeholders
SERVICE_CONTENT=$(cat "$TEMPLATE_FILE")
SERVICE_CONTENT="${SERVICE_CONTENT//\{\{SERVICE_DESCRIPTION\}\}/${DESCRIPTION}}"
SERVICE_CONTENT="${SERVICE_CONTENT//\{\{SERVICE_USER\}\}/${SERVICE_USER}}"
SERVICE_CONTENT="${SERVICE_CONTENT//\{\{WORK_DIR\}\}/${WORK_DIR}}"
SERVICE_CONTENT="${SERVICE_CONTENT//\{\{EXEC_COMMAND\}\}/${EXEC_COMMAND}}"
SERVICE_CONTENT="${SERVICE_CONTENT//\{\{ENV_FILE\}\}/${ENV_FILE}}"

# Write service file
OUTPUT_FILE="${SERVICE_DIR}/${SERVICE_NAME}.service"
echo "Generating systemd service: $OUTPUT_FILE"
echo "$SERVICE_CONTENT" > "$OUTPUT_FILE"

# Reload systemd daemon
echo "Reloading systemd daemon..."
systemctl daemon-reload

echo ""
echo "Service generated successfully!"
echo "  Name:        ${SERVICE_NAME}"
echo "  Description: ${DESCRIPTION}"
echo "  Exec:        ${EXEC_COMMAND}"
echo "  User:        ${SERVICE_USER}"
echo "  WorkDir:     ${WORK_DIR}"
echo "  EnvFile:     ${ENV_FILE}"
echo "  File:        $OUTPUT_FILE"
echo ""
echo "Next steps:"
echo "  1. Review the service: cat $OUTPUT_FILE"
echo "  2. Create env file if needed: touch $ENV_FILE"
echo "  3. Start the service: systemctl start ${SERVICE_NAME}"
echo "  4. Enable on boot:   systemctl enable ${SERVICE_NAME}"
echo "  5. Check status:      systemctl status ${SERVICE_NAME}"
