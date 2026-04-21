#!/bin/bash
set -euo pipefail

# Post-deployment health check script
# Usage: bash health-check.sh --url <url> [--expected-status <code>] [--expected-text <text>] [--timeout <seconds>]

usage() {
    echo "Usage: bash health-check.sh --url <url> [--expected-status <code>] [--expected-text <text>] [--timeout <seconds>]"
    exit 1
}

URL=""
EXPECTED_STATUS="200"
EXPECTED_TEXT=""
TIMEOUT="30"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)
            URL="$2"
            shift 2
            ;;
        --expected-status)
            EXPECTED_STATUS="$2"
            shift 2
            ;;
        --expected-text)
            EXPECTED_TEXT="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -z "$URL" ]]; then
    echo "Error: --url is required"
    usage
fi

# Initialize result variables
HTTP_STATUS=0
RESPONSE_TIME_MS=0
SSL_VALID="false"
SSL_EXPIRY_DAYS=-1
CONTENT_CHECK="skipped"
OVERALL="unhealthy"

# Function to check SSL certificate
check_ssl() {
    local host
    host=$(echo "$URL" | sed -E 's|^https?://([^/:]+).*|\1|')

    if ! END_DATE=$(echo | openssl s_client -connect "${host}:443" -servername "${host}" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null); then
        SSL_VALID="false"
        SSL_EXPIRY_DAYS=-1
        return
    fi

    if [[ -z "$END_DATE" ]]; then
        SSL_VALID="false"
        SSL_EXPIRY_DAYS=-1
        return
    fi

    # Parse expiry date (format: notAfter=Mon DD HH:MM:SS YYYY GMT)
    EXPIRY_STR=$(echo "$END_DATE" | sed 's/notAfter=//')
    if [[ "$(uname)" == "Darwin" ]]; then
        EXPIRY_EPOCH=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$EXPIRY_STR" "+%s" 2>/dev/null || echo "0")
    else
        EXPIRY_EPOCH=$(date -d "$EXPIRY_STR" "+%s" 2>/dev/null || echo "0")
    fi

    NOW_EPOCH=$(date "+%s")

    if [[ "$EXPIRY_EPOCH" -eq 0 ]]; then
        SSL_VALID="false"
        SSL_EXPIRY_DAYS=-1
        return
    fi

    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

    if [[ "$DAYS_LEFT" -gt 0 ]]; then
        SSL_VALID="true"
        SSL_EXPIRY_DAYS="$DAYS_LEFT"
    else
        SSL_VALID="false"
        SSL_EXPIRY_DAYS="$DAYS_LEFT"
    fi
}

# Check HTTP status and response time
check_http() {
    local curl_output
    curl_output=$(curl -o /dev/null -s -w '%{http_code} %{time_total}' \
        --max-time "$TIMEOUT" \
        --connect-timeout "$TIMEOUT" \
        "$URL" 2>&1) || true

    if [[ -z "$curl_output" ]]; then
        HTTP_STATUS=0
        RESPONSE_TIME_MS=0
        return
    fi

    HTTP_STATUS=$(echo "$curl_output" | awk '{print $1}')
    local time_total
    time_total=$(echo "$curl_output" | awk '{print $2}')

    # Convert seconds to milliseconds
    RESPONSE_TIME_MS=$(echo "$time_total" | awk '{printf "%.0f", $1 * 1000}')
}

# Check for expected text in response body
check_content() {
    if [[ -z "$EXPECTED_TEXT" ]]; then
        CONTENT_CHECK="skipped"
        return
    fi

    local body
    body=$(curl -s --max-time "$TIMEOUT" --connect-timeout "$TIMEOUT" "$URL" 2>/dev/null) || true

    if echo "$body" | grep -q "$EXPECTED_TEXT"; then
        CONTENT_CHECK="passed"
    else
        CONTENT_CHECK="failed"
    fi
}

# Determine overall health
check_overall() {
    OVERALL="healthy"

    if [[ "$HTTP_STATUS" != "$EXPECTED_STATUS" ]]; then
        OVERALL="unhealthy"
        return
    fi

    if [[ "$URL" == https://* ]]; then
        if [[ "$SSL_VALID" != "true" ]]; then
            OVERALL="unhealthy"
            return
        fi
    fi

    if [[ "$CONTENT_CHECK" == "failed" ]]; then
        OVERALL="unhealthy"
        return
    fi
}

# Run checks
check_http

if [[ "$URL" == https://* ]]; then
    check_ssl
else
    SSL_VALID="null"
    SSL_EXPIRY_DAYS="null"
fi

check_content
check_overall

# Output JSON result
cat <<EOF
{
  "url": "${URL}",
  "http_status": ${HTTP_STATUS},
  "response_time_ms": ${RESPONSE_TIME_MS},
  "ssl_valid": ${SSL_VALID},
  "ssl_expiry_days": ${SSL_EXPIRY_DAYS},
  "content_check": "${CONTENT_CHECK}",
  "overall": "${OVERALL}"
}
EOF
