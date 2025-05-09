#!/bin/bash
# SysAdmin Vault Raft Snapshot Management Script
# This script takes Vault Raft snapshots and manages retention
# Designed to be run as a cron job by the System Administrator

# Configuration variables - modify as needed
VAULT_ADDR=${VAULT_ADDR:-"http://127.0.0.1:8200"}
SNAPSHOT_DIR="/opt/vault/snapshots"
RETENTION_DAYS=14
LOG_FILE="/var/log/vault-snapshots.log"
# Need to figure out where to run the script and what auth method to use.
VAULT_TOKEN_FILE="/etc/vault/vault-token"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Ensure the snapshot directory exists
if [ ! -d "$SNAPSHOT_DIR" ]; then
    mkdir -p "$SNAPSHOT_DIR"
    chmod 750 "$SNAPSHOT_DIR"
    log "Created snapshot directory: $SNAPSHOT_DIR"
fi

# Ensure the log file exists and has proper permissions
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    log "Initialized snapshot log file"
fi

# Check for vault binary
if ! command -v vault &> /dev/null; then
    log "ERROR: Vault CLI not found. Please install Vault or add it to PATH."
    exit 1
fi

# Get Vault token
if [ -f "$VAULT_TOKEN_FILE" ]; then
    VAULT_TOKEN=$(cat "$VAULT_TOKEN_FILE")
    export VAULT_TOKEN
    log "Using token from $VAULT_TOKEN_FILE"
else
    if [ -z "$VAULT_TOKEN" ]; then
        log "ERROR: No Vault token provided. Please set VAULT_TOKEN environment variable or create $VAULT_TOKEN_FILE"
        exit 1
    else
        log "Using VAULT_TOKEN from environment"
    fi
fi

# Set Vault address
export VAULT_ADDR
log "Using Vault address: $VAULT_ADDR"

# Create timestamp for the snapshot filename
TIMESTAMP=$(date "+%Y%m%d-%H%M%S")
SNAPSHOT_FILE="$SNAPSHOT_DIR/vault-raft-snapshot-$TIMESTAMP.snap"

# Take the snapshot
log "Taking Raft snapshot..."
if vault operator raft snapshot save "$SNAPSHOT_FILE" 2>> "$LOG_FILE"; then
    chmod 640 "$SNAPSHOT_FILE"
    log "SUCCESS: Snapshot saved to $SNAPSHOT_FILE"
else
    log "ERROR: Failed to take Raft snapshot. Check Vault status and permissions."
    exit 1
fi

# Clean up old snapshots based on retention policy
log "Cleaning up snapshots older than $RETENTION_DAYS days..."
find "$SNAPSHOT_DIR" -name "vault-raft-snapshot-*.snap" -type f -mtime +$RETENTION_DAYS -exec rm -f {} \; 2>/dev/null
if [ $? -eq 0 ]; then
    log "Cleanup completed successfully"
else
    log "WARNING: Issue during snapshot cleanup"
fi

# Count remaining snapshots
SNAPSHOT_COUNT=$(find "$SNAPSHOT_DIR" -name "vault-raft-snapshot-*.snap" | wc -l)
log "Currently storing $SNAPSHOT_COUNT snapshots in $SNAPSHOT_DIR"

log "Raft snapshot process completed"
exit 0 