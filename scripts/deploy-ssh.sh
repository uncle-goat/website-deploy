#!/bin/bash
set -euo pipefail

# SSH remote deployment script
# Usage: bash deploy-ssh.sh --host <host> --user <user> [--key <key-path>] [--source <local-path>] [--remote-path <remote-path>] [--post-deploy <commands>]

usage() {
    echo "Usage: bash deploy-ssh.sh --host <host> --user <user> [--key <key-path>] [--source <local-path>] [--remote-path <remote-path>] [--post-deploy <commands>]"
    exit 1
}

HOST=""
USER=""
KEY=""
SOURCE="./"
REMOTE_PATH="/var/www/app"
POST_DEPLOY=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            HOST="$2"
            shift 2
            ;;
        --user)
            USER="$2"
            shift 2
            ;;
        --key)
            KEY="$2"
            shift 2
            ;;
        --source)
            SOURCE="$2"
            shift 2
            ;;
        --remote-path)
            REMOTE_PATH="$2"
            shift 2
            ;;
        --post-deploy)
            POST_DEPLOY="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -z "$HOST" || -z "$USER" ]]; then
    echo "Error: --host and --user are required"
    usage
fi

# Build SSH options
SSH_OPTS="-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
if [[ -n "$KEY" ]]; then
    if [[ ! -f "$KEY" ]]; then
        echo "Error: SSH key not found: $KEY"
        exit 1
    fi
    SSH_OPTS="$SSH_OPTS -i $KEY"
fi

# Build SSH command
SSH_CMD="ssh $SSH_OPTS ${USER}@${HOST}"

# Step 1: Check SSH connectivity
echo "==> Checking SSH connectivity to ${USER}@${HOST}..."
if ! $SSH_CMD "echo 'SSH connection successful'" 2>/dev/null; then
    echo "Error: SSH connection failed to ${USER}@${HOST}"
    echo "  - Check that the host is reachable"
    echo "  - Verify SSH key permissions (chmod 600)"
    echo "  - Ensure public key is added to remote ~/.ssh/authorized_keys"
    exit 1
fi
echo "    SSH connection: OK"

# Step 2: Ensure remote directory exists
echo "==> Ensuring remote directory exists: ${REMOTE_PATH}"
$SSH_CMD "mkdir -p ${REMOTE_PATH}" 2>/dev/null
echo "    Remote directory: OK"

# Step 3: Transfer files using rsync
echo "==> Transferring files from ${SOURCE} to ${USER}@${HOST}:${REMOTE_PATH}..."

RSYNC_OPTS="-avz --delete"
RSYNC_OPTS="$RSYNC_OPTS --exclude=node_modules"
RSYNC_OPTS="$RSYNC_OPTS --exclude=.git"
RSYNC_OPTS="$RSYNC_OPTS --exclude=__pycache__"
RSYNC_OPTS="$RSYNC_OPTS --exclude=.venv"
RSYNC_OPTS="$RSYNC_OPTS --exclude=venv"
RSYNC_OPTS="$RSYNC_OPTS --exclude=dist"
RSYNC_OPTS="$RSYNC_OPTS --exclude=.next"

if [[ -n "$KEY" ]]; then
    RSYNC_OPTS="$RSYNC_OPTS -e 'ssh -i $KEY -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new'"
else
    RSYNC_OPTS="$RSYNC_OPTS -e 'ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new'"
fi

# Use eval to handle the -e option with quotes properly
if ! eval rsync $RSYNC_OPTS "${SOURCE}/" "${USER}@${HOST}:${REMOTE_PATH}/" 2>&1; then
    echo "Error: rsync transfer failed"
    echo "  - Check that rsync is installed on both local and remote"
    echo "  - Verify file permissions"
    echo "  - Ensure remote disk has sufficient space"
    exit 1
fi
echo "    File transfer: OK"

# Step 4: Execute post-deploy commands
if [[ -n "$POST_DEPLOY" ]]; then
    echo "==> Executing post-deploy commands..."
    echo "    Commands: ${POST_DEPLOY}"

    if ! $SSH_CMD "cd ${REMOTE_PATH} && ${POST_DEPLOY}" 2>&1; then
        echo "Error: Post-deploy commands failed"
        exit 1
    fi
    echo "    Post-deploy: OK"
else
    echo "==> No post-deploy commands specified, skipping."
fi

# Done
echo ""
echo "==> Deployment completed successfully!"
echo "    Host:       ${USER}@${HOST}"
echo "    Source:     ${SOURCE}"
echo "    Remote:     ${REMOTE_PATH}"
echo "    Post-deploy: ${POST_DEPLOY:-"(none)"}"
