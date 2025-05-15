#!/bin/bash
##############################################################################
# Vault Raft Snapshot Management Script
#
# PURPOSE:
# This script is used by System Administrators to create and manage snapshots
# of a Vault cluster using the Raft storage backend. It handles both creating
# new snapshots and maintaining a retention policy for older snapshots.
#
# DISASTER RECOVERY:
# Regular snapshots are a critical component of a disaster recovery strategy
# for Vault. They allow restoring Vault's state in case of data corruption,
# accidental deletion, or infrastructure failure.
#
# WORKFLOW:
# 1. Validates the environment and configuration
# 2. Takes a timestamped snapshot of the Vault Raft storage
# 3. Sets proper permissions on the snapshot file
# 4. Removes old snapshots based on the configured retention period
# 5. Logs all actions for auditability
#
# RECOMMENDED USAGE:
# Set this script to run as a cron job, e.g.:
# 0 2 * * * /path/to/sysadmin-raft-snapshot.sh
##############################################################################

# Configuration variables - modify these as appropriate for your environment
VAULT_ADDR=${VAULT_ADDR:-"http://127.0.0.1:8200"}  # Default Vault server address
SNAPSHOT_DIR="/opt/vault/snapshots"                # Where snapshots will be stored
RETENTION_DAYS=14                                  # How many days to keep snapshots
LOG_FILE="/var/log/vault-snapshots.log"            # Where to log script activity
VAULT_TOKEN_FILE="/etc/vault/vault-token"          # File containing Vault token

# ANSI color codes for better terminal output readability
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ----------------------------------------------------------------------------
# Logging function to provide consistent formatting and dual logging
# (both to console and log file)
# ----------------------------------------------------------------------------
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
    echo "[$timestamp] $1"
}

# ----------------------------------------------------------------------------
# Environment setup and validation
# ----------------------------------------------------------------------------
# Ensure the snapshot directory exists with proper permissions
if [ ! -d "$SNAPSHOT_DIR" ]; then
    mkdir -p "$SNAPSHOT_DIR"
    chmod 750 "$SNAPSHOT_DIR"  # Restrictive permissions to protect snapshot content
    log "Created snapshot directory: $SNAPSHOT_DIR"
fi

# Ensure the log file exists with proper permissions
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"  # Allow reading by specific groups but restrict wider access
    log "Initialized snapshot log file"
fi

# Verify vault CLI is installed and accessible
if ! command -v vault &> /dev/null; then
    log "ERROR: Vault CLI not found. Please install Vault or add it to PATH."
    exit 1
fi

# ----------------------------------------------------------------------------
# Authentication - get Vault token from file or environment
# ----------------------------------------------------------------------------
if [ -f "$VAULT_TOKEN_FILE" ]; then
    # Using token from file is more secure for automated scripts than
    # hardcoding tokens in scripts or cron jobs
    VAULT_TOKEN=$(cat "$VAULT_TOKEN_FILE")
    export VAULT_TOKEN
    log "Using token from $VAULT_TOKEN_FILE"
else
    # Fall back to environment variable if file doesn't exist
    if [ -z "$VAULT_TOKEN" ]; then
        log "ERROR: No Vault token provided. Please set VAULT_TOKEN environment variable or create $VAULT_TOKEN_FILE"
        log "HINT: The token needs 'operator/raft' capabilities for snapshot operations"
        exit 1
    else
        log "Using VAULT_TOKEN from environment"
    fi
fi

# Export Vault address for the CLI commands
export VAULT_ADDR
log "Using Vault address: $VAULT_ADDR"

# ----------------------------------------------------------------------------
# Take the snapshot with timestamp in filename for uniqueness
# ----------------------------------------------------------------------------
# Create timestamp format: YYYYMMDD-HHMMSS
TIMESTAMP=$(date "+%Y%m%d-%H%M%S")
SNAPSHOT_FILE="$SNAPSHOT_DIR/vault-raft-snapshot-$TIMESTAMP.snap"

# Execute the snapshot command
log "Taking Raft snapshot..."
if vault operator raft snapshot save "$SNAPSHOT_FILE" 2>> "$LOG_FILE"; then
    # Set secure permissions on the snapshot file to prevent unauthorized access
    # Snapshots contain sensitive Vault data and should be protected
    chmod 640 "$SNAPSHOT_FILE"
    log "SUCCESS: Snapshot saved to $SNAPSHOT_FILE"
else
    log "ERROR: Failed to take Raft snapshot. Check Vault status and permissions."
    log "Make sure the token has the necessary permissions for 'vault operator raft' commands."
    exit 1
fi

# ----------------------------------------------------------------------------
# Clean up old snapshots based on retention policy
# ----------------------------------------------------------------------------
log "Cleaning up snapshots older than $RETENTION_DAYS days..."
# Find and remove snapshot files older than the retention period
# Using -mtime +N to find files older than N days
find "$SNAPSHOT_DIR" -name "vault-raft-snapshot-*.snap" -type f -mtime +$RETENTION_DAYS -exec rm -f {} \; 2>/dev/null
if [ $? -eq 0 ]; then
    log "Cleanup completed successfully"
else
    log "WARNING: Issue during snapshot cleanup"
fi

# ----------------------------------------------------------------------------
# Report snapshot status
# ----------------------------------------------------------------------------
# Count the number of snapshots for reporting purposes
SNAPSHOT_COUNT=$(find "$SNAPSHOT_DIR" -name "vault-raft-snapshot-*.snap" | wc -l)
log "Currently storing $SNAPSHOT_COUNT snapshots in $SNAPSHOT_DIR"
log "Oldest snapshot: $(find "$SNAPSHOT_DIR" -name "vault-raft-snapshot-*.snap" | sort | head -1)"
log "Newest snapshot: $SNAPSHOT_FILE"
log "Total space used: $(du -sh "$SNAPSHOT_DIR" | cut -f1)"

log "Raft snapshot process completed"
exit 0 