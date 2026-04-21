#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<EOF
Usage: bash generate-nginx-config.sh --type <reverse-proxy|static> --domain <domain> [options]

Options:
  --type <reverse-proxy|static>   Configuration type (required)
  --domain <domain>               Domain name (required)
  --upstream <host:port>          Upstream address for reverse-proxy (e.g., 127.0.0.1:3000)
  --upstream-port <port>          Upstream port only (will use 127.0.0.1:<port>)
  --static-path <path>            Static files root path (for static type)
  --output-dir <path>             Output directory (default: /etc/nginx/sites-available)
  -h, --help                      Show this help message

Examples:
  # Reverse proxy with upstream address
  bash generate-nginx-config.sh --type reverse-proxy --domain example.com --upstream 127.0.0.1:3000

  # Reverse proxy with upstream port only
  bash generate-nginx-config.sh --type reverse-proxy --domain example.com --upstream-port 3000

  # Static site
  bash generate-nginx-config.sh --type static --domain example.com --static-path /var/www/html
EOF
    exit "${1:-0}"
}

# Parse arguments
TYPE=""
DOMAIN=""
UPSTREAM=""
UPSTREAM_PORT=""
STATIC_PATH=""
OUTPUT_DIR="/etc/nginx/sites-available"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --type)
            TYPE="$2"
            shift 2
            ;;
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --upstream)
            UPSTREAM="$2"
            shift 2
            ;;
        --upstream-port)
            UPSTREAM_PORT="$2"
            shift 2
            ;;
        --static-path)
            STATIC_PATH="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
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
if [[ -z "$TYPE" ]]; then
    echo "Error: --type is required" >&2
    usage 1
fi

if [[ -z "$DOMAIN" ]]; then
    echo "Error: --domain is required" >&2
    usage 1
fi

# Validate type-specific requirements
if [[ "$TYPE" == "reverse-proxy" ]]; then
    if [[ -n "$UPSTREAM_PORT" ]]; then
        UPSTREAM="127.0.0.1:${UPSTREAM_PORT}"
    fi
    if [[ -z "$UPSTREAM" ]]; then
        echo "Error: --upstream or --upstream-port is required for reverse-proxy type" >&2
        usage 1
    fi
    TEMPLATE_FILE="${SCRIPT_DIR}/../templates/nginx-reverse-proxy.conf"
elif [[ "$TYPE" == "static" ]]; then
    if [[ -z "$STATIC_PATH" ]]; then
        echo "Error: --static-path is required for static type" >&2
        usage 1
    fi
    TEMPLATE_FILE="${SCRIPT_DIR}/../templates/nginx-static.conf"
else
    echo "Error: Invalid type '$TYPE'. Must be 'reverse-proxy' or 'static'" >&2
    usage 1
fi

# Check template file exists
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "Error: Template file not found: $TEMPLATE_FILE" >&2
    exit 1
fi

# Create output directory if it doesn't exist
if [[ ! -d "$OUTPUT_DIR" ]]; then
    echo "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

# Read template and replace placeholders
CONFIG_CONTENT=$(cat "$TEMPLATE_FILE")
CONFIG_CONTENT="${CONFIG_CONTENT//\{\{DOMAIN\}\}/${DOMAIN}}"

if [[ "$TYPE" == "reverse-proxy" ]]; then
    CONFIG_CONTENT="${CONFIG_CONTENT//\{\{UPSTREAM\}\}/${UPSTREAM}}"
elif [[ "$TYPE" == "static" ]]; then
    CONFIG_CONTENT="${CONFIG_CONTENT//\{\{STATIC_PATH\}\}/${STATIC_PATH}}"
fi

# Write output file
OUTPUT_FILE="${OUTPUT_DIR}/${DOMAIN}.conf"
echo "Generating Nginx config: $OUTPUT_FILE"
echo "$CONFIG_CONTENT" > "$OUTPUT_FILE"

# Create symlink to sites-enabled if output is the default nginx path
SITES_ENABLED="/etc/nginx/sites-enabled"
if [[ "$OUTPUT_DIR" == "/etc/nginx/sites-available" ]] && [[ -d "$SITES_ENABLED" ]]; then
    ln -sf "$OUTPUT_FILE" "${SITES_ENABLED}/${DOMAIN}.conf"
    echo "Symlink created: ${SITES_ENABLED}/${DOMAIN}.conf -> $OUTPUT_FILE"
fi

echo ""
echo "Configuration generated successfully!"
echo "  Type:     $TYPE"
echo "  Domain:   $DOMAIN"
if [[ "$TYPE" == "reverse-proxy" ]]; then
    echo "  Upstream: $UPSTREAM"
elif [[ "$TYPE" == "static" ]]; then
    echo "  Path:     $STATIC_PATH"
fi
echo "  Output:   $OUTPUT_FILE"
echo ""
echo "Next steps:"
echo "  1. Review the config: cat $OUTPUT_FILE"
echo "  2. Test Nginx config: nginx -t"
echo "  3. Reload Nginx: systemctl reload nginx"
