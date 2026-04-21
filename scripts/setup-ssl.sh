#!/bin/bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: bash setup-ssl.sh --domain <domain> --email <email> [--nginx] [--standalone] [--webroot <path>]

Options:
  --domain <domain>       Domain name (required)
  --email <email>         Email for Let's Encrypt registration (required)
  --nginx                 Use Nginx plugin for certificate (default mode)
  --standalone            Use standalone mode (stops Nginx temporarily)
  --webroot <path>        Use webroot mode with specified path
  -h, --help              Show this help message

Examples:
  # Using Nginx plugin (recommended)
  bash setup-ssl.sh --domain example.com --email admin@example.com --nginx

  # Using standalone mode
  bash setup-ssl.sh --domain example.com --email admin@example.com --standalone

  # Using webroot mode
  bash setup-ssl.sh --domain example.com --email admin@example.com --webroot /var/www/html
EOF
    exit "${1:-0}"
}

# Parse arguments
DOMAIN=""
EMAIL=""
MODE="nginx"
WEBROOT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --nginx)
            MODE="nginx"
            shift
            ;;
        --standalone)
            MODE="standalone"
            shift
            ;;
        --webroot)
            MODE="webroot"
            WEBROOT_PATH="$2"
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
if [[ -z "$DOMAIN" ]]; then
    echo "Error: --domain is required" >&2
    usage 1
fi

if [[ -z "$EMAIL" ]]; then
    echo "Error: --email is required" >&2
    usage 1
fi

if [[ "$MODE" == "webroot" && -z "$WEBROOT_PATH" ]]; then
    echo "Error: --webroot <path> is required when using webroot mode" >&2
    usage 1
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)." >&2
    exit 1
fi

echo "============================================"
echo " SSL Certificate Setup"
echo "============================================"
echo "  Domain: $DOMAIN"
echo "  Email:  $EMAIL"
echo "  Mode:   $MODE"
echo "============================================"
echo ""

# Step 1: Check and install certbot
echo "[1/5] Checking certbot installation..."
if command -v certbot &>/dev/null; then
    CERTBOT_CMD="certbot"
    echo "  certbot is already installed: $(certbot --version 2>&1)"
else
    echo "  certbot is not installed. Installing..."
    if command -v apt-get &>/dev/null; then
        apt-get update -y
        apt-get install -y certbot
        if [[ "$MODE" == "nginx" ]]; then
            apt-get install -y python3-certbot-nginx
        fi
    elif command -v yum &>/dev/null; then
        yum install -y epel-release
        yum install -y certbot
        if [[ "$MODE" == "nginx" ]]; then
            yum install -y python3-certbot-nginx
        fi
    elif command -v dnf &>/dev/null; then
        dnf install -y certbot
        if [[ "$MODE" == "nginx" ]]; then
            dnf install -y python3-certbot-nginx
        fi
    else
        echo "Error: Unable to detect package manager. Please install certbot manually." >&2
        exit 1
    fi
    CERTBOT_CMD="certbot"
    echo "  certbot installed successfully: $(certbot --version 2>&1)"
fi

# Step 2: Check port 80 accessibility
echo ""
echo "[2/5] Checking port 80 accessibility..."
if command -v ss &>/dev/null; then
    PORT_CHECK=$(ss -tlnp 2>/dev/null | grep ':80 ' || true)
elif command -v netstat &>/dev/null; then
    PORT_CHECK=$(netstat -tlnp 2>/dev/null | grep ':80 ' || true)
else
    PORT_CHECK=""
fi

if [[ -n "$PORT_CHECK" ]]; then
    echo "  Port 80 is in use:"
    echo "  $PORT_CHECK"
else
    echo "  Warning: Port 80 does not appear to be in use."
    echo "  Make sure your domain DNS points to this server's IP address."
fi

# Step 3: Obtain certificate
echo ""
echo "[3/5] Obtaining SSL certificate for $DOMAIN..."

CERTBOT_ARGS=(
    --non-interactive
    --agree-tos
    --email "$EMAIL"
    -d "$DOMAIN"
)

case "$MODE" in
    nginx)
        echo "  Using Nginx plugin..."
        certbot --nginx "${CERTBOT_ARGS[@]}"
        ;;
    standalone)
        echo "  Using standalone mode..."
        # Stop Nginx temporarily if running
        NGINX_WAS_RUNNING=false
        if systemctl is-active --quiet nginx 2>/dev/null; then
            echo "  Stopping Nginx temporarily..."
            systemctl stop nginx
            NGINX_WAS_RUNNING=true
        fi
        certbot certonly --standalone "${CERTBOT_ARGS[@]}"
        # Restart Nginx if it was running
        if [[ "$NGINX_WAS_RUNNING" == true ]]; then
            echo "  Restarting Nginx..."
            systemctl start nginx
        fi
        ;;
    webroot)
        echo "  Using webroot mode (path: $WEBROOT_PATH)..."
        mkdir -p "${WEBROOT_PATH}/.well-known/acme-challenge"
        certbot certonly --webroot -w "$WEBROOT_PATH" "${CERTBOT_ARGS[@]}"
        ;;
    *)
        echo "Error: Unknown mode '$MODE'" >&2
        exit 1
        ;;
esac

# Step 4: Set up auto-renewal cron
echo ""
echo "[4/5] Setting up auto-renewal cron job..."
CRON_JOB="0 3 * * * certbot renew --quiet"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "certbot renew"; then
    echo "  Auto-renewal cron job already exists. Skipping."
else
    # Add cron job, preserving existing crontab
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "  Auto-renewal cron job added: $CRON_JOB"
fi

# Also deploy the renewal hook for systemd timer (if available)
if [[ -d /etc/systemd/system ]]; then
    if [[ -f /etc/systemd/system/certbot.timer ]] || systemctl list-timers certbot.timer &>/dev/null; then
        echo "  systemd certbot timer is already active."
    fi
fi

# Step 5: Verify certificate
echo ""
echo "[5/5] Verifying SSL certificate..."
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"

if [[ -f "$CERT_PATH" ]]; then
    echo "  Certificate file found: $CERT_PATH"

    # Display certificate info
    echo ""
    echo "  Certificate details:"
    openssl x509 -in "$CERT_PATH" -noout -subject -dates -issuer 2>/dev/null | sed 's/^/    /' || echo "    (unable to read certificate details)"

    # Test SSL connection
    echo ""
    echo "  Testing SSL connection on port 443..."
    if timeout 10 openssl s_client -connect "${DOMAIN}:443" -servername "$DOMAIN" </dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
        echo "  SSL connection verified successfully!"
    else
        echo "  Warning: Could not verify SSL connection on port 443."
        echo "  This may be expected if Nginx SSL config has not been updated yet."
        echo "  Make sure to uncomment the SSL server block in your Nginx config."
    fi
else
    echo "  Warning: Certificate file not found at $CERT_PATH"
    echo "  The certificate may have been saved to a different location."
    echo "  Check certbot output above for details."
fi

echo ""
echo "============================================"
echo " SSL Setup Complete!"
echo "============================================"
echo ""
echo "Certificate paths:"
echo "  Full chain:  /etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
echo "  Private key: /etc/letsencrypt/live/${DOMAIN}/privkey.pem"
echo ""
echo "Next steps:"
echo "  1. Update your Nginx config to use the SSL certificate"
echo "  2. Uncomment the SSL server block in your Nginx config"
echo "  3. Test Nginx config: nginx -t"
echo "  4. Reload Nginx: systemctl reload nginx"
echo ""
echo "To test certificate renewal:"
echo "  certbot renew --dry-run"
