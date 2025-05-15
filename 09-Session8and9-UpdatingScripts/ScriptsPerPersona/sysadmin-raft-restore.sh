#!/bin/bash
##############################################################################
# Vault Raft Snapshot Restoration Script
#
# PURPOSE:
# This script facilitates the restoration of a Vault cluster from a Raft snapshot
# during disaster recovery scenarios. It provides a guided, interactive process
# to ensure safe restoration with proper verification and safeguards.
#
# CONTEXT:
# Snapshot restoration is a critical operation that replaces all data in Vault.
# It should only be performed during disaster recovery or as part of a planned
# migration. This operation completely replaces the current state of Vault with
# the state from the snapshot.
#
# CRITICAL CONSIDERATIONS:
# - All tokens, leases, and secrets created after the snapshot was taken will be lost
# - Authentication may be required after restoration
# - The operation should generally be performed on the leader node
# - Proper authorization and a maintenance window are required
# - Multiple confirmations are built into the script to prevent accidental execution
#
# WORKFLOW:
# 1. Validates the environment and dependencies
# 2. Authenticates to Vault with appropriate privileges
# 3. Verifies the current state of Vault and the target node
# 4. Lists and selects a snapshot from the snapshot directory
# 5. Restores the selected snapshot after multiple confirmations
# 6. Verifies the restoration was successful
# 7. Provides guidance on post-restoration steps
#
# PERMISSIONS REQUIRED:
# - Operator privileges for Vault (specifically 'operator/raft' capabilities)
# - File system access to the snapshot directory
##############################################################################

# ----------------------------------------------------------------------------
# Configuration variables - modify as appropriate for your environment
# ----------------------------------------------------------------------------
SNAPSHOT_DIR="/opt/vault/snapshots"     # Directory containing Vault snapshots
LOG_FILE="/var/log/vault-restore.log"   # Path to log file for restore operations

# ANSI color codes for better terminal output readability
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# ----------------------------------------------------------------------------
# Logging function - writes to both console and log file
# ----------------------------------------------------------------------------
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
    echo -e "[$timestamp] $1"
}

# ----------------------------------------------------------------------------
# Initial banner and warning message
# ----------------------------------------------------------------------------
echo -e "\n${BLUE}=== SysAdmin Vault Raft Snapshot Restoration Tool ===${NC}"
echo "This interactive tool will guide you through restoring a Vault instance from a snapshot."
echo "It is critical that this is run with proper authorization and during a planned maintenance window."
echo ""

# ----------------------------------------------------------------------------
# Environment setup and validation
# ----------------------------------------------------------------------------
# Ensure the log file exists with secure permissions
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"  # Secure permissions for the log file
    log "Initialized restore log file"
fi

# Verify Vault CLI is installed and accessible
if ! command -v vault &> /dev/null; then
    log "${RED}ERROR: Vault CLI not found. Please install Vault or add it to PATH.${NC}"
    log "Visit https://developer.hashicorp.com/vault/downloads for installation instructions."
    exit 1
fi

# Verify jq is installed - needed for JSON parsing
if ! command -v jq &> /dev/null; then
    log "${RED}ERROR: jq is not installed. It's required for parsing Vault responses.${NC}"
    log "Install using: apt-get install jq (Debian/Ubuntu) or yum install jq (CentOS/RHEL)"
    exit 1
fi

# ----------------------------------------------------------------------------
# Vault connectivity configuration
# ----------------------------------------------------------------------------
# Configure Vault server address if not already set in environment
if [ -z "$VAULT_ADDR" ]; then
    DEFAULT_VAULT_ADDR="http://127.0.0.1:8200"
    read -p "Enter Vault server address [$DEFAULT_VAULT_ADDR]: " input_addr
    VAULT_ADDR=${input_addr:-$DEFAULT_VAULT_ADDR}
fi
export VAULT_ADDR  # Export for Vault CLI to use
log "Using Vault address: $VAULT_ADDR"

# ----------------------------------------------------------------------------
# Authentication to Vault with appropriate privileges
# ----------------------------------------------------------------------------
if [ -z "$VAULT_TOKEN" ]; then
    echo -e "\n${BLUE}Select authentication method:${NC}"
    echo "1. Token (direct entry)"
    echo "2. Token (from file)"
    echo "3. LDAP"
    read -p "Choice [1]: " auth_method
    auth_method=${auth_method:-1}
    
    case $auth_method in
        1)
            # Interactive token entry
            echo "Please authenticate to Vault with your token:"
            vault login
            ;;
        2)
            # Read token from file (useful for automation or to avoid token in shell history)
            read -p "Enter path to token file [/etc/vault/vault-token]: " token_file
            token_file=${token_file:-"/etc/vault/vault-token"}
            
            if [ -f "$token_file" ]; then
                VAULT_TOKEN=$(cat "$token_file")
                export VAULT_TOKEN
                log "Using token from $token_file"
                
                # Verify token has required permissions
                if ! vault token lookup &>/dev/null; then
                    log "${RED}ERROR: Invalid token in $token_file. Please check the token and try again.${NC}"
                    exit 1
                fi
                log "Token verification successful"
            else
                log "${RED}ERROR: Token file $token_file does not exist.${NC}"
                exit 1
            fi
            ;;
        3)
            # LDAP authentication (requires LDAP auth method to be enabled)
            read -p "Enter LDAP username: " ldap_username
            echo "You will be prompted for your LDAP password next (input will not be displayed)"
            if ! vault login -method=ldap username="$ldap_username"; then
                log "${RED}ERROR: LDAP authentication failed.${NC}"
                exit 1
            fi
            ;;
        *)
            # Default fallback for invalid input
            log "${RED}Invalid choice. Defaulting to token authentication.${NC}"
            vault login
            ;;
    esac
fi

# ----------------------------------------------------------------------------
# Snapshot directory validation
# ----------------------------------------------------------------------------
# Check if the configured snapshot directory exists, prompt for alternative if not
if [ ! -d "$SNAPSHOT_DIR" ]; then
    log "${YELLOW}Snapshot directory $SNAPSHOT_DIR does not exist.${NC}"
    read -p "Enter the path to snapshot directory: " custom_snapshot_dir
    if [ -d "$custom_snapshot_dir" ]; then
        SNAPSHOT_DIR="$custom_snapshot_dir"
        log "Using custom snapshot directory: $SNAPSHOT_DIR"
    else
        log "${RED}ERROR: Specified directory does not exist.${NC}"
        exit 1
    fi
fi

# ----------------------------------------------------------------------------
# Vault server connectivity verification
# ----------------------------------------------------------------------------
log "Verifying Vault server is accessible..."
if ! vault status &> /dev/null; then
    log "${RED}ERROR: Vault server is not running or not accessible at $VAULT_ADDR.${NC}"
    log "Please check that Vault is running and the address is correct."
    exit 1
fi
log "${GREEN}Vault server is accessible.${NC}"

# ----------------------------------------------------------------------------
# Pre-restoration Vault status check
# ----------------------------------------------------------------------------
# Record the state before restoration for comparison
log "Checking Vault status before restoration..."
vault_status_before=$(vault status -format=json 2>/dev/null)
if [ $? -ne 0 ]; then
    log "${RED}ERROR: Unable to get Vault status. Ensure Vault is running and accessible.${NC}"
    exit 1
fi

# Extract key metrics from Vault status for comparison after restoration
raft_applied_index_before=$(echo "$vault_status_before" | jq -r '.raft_applied_index // "unknown"')
ha_mode_before=$(echo "$vault_status_before" | jq -r '.ha_mode // "unknown"')
log "Current Vault Status:"
log "- HA Mode: $ha_mode_before"
log "- Raft Applied Index: $raft_applied_index_before"

# ----------------------------------------------------------------------------
# Leader node verification
# ----------------------------------------------------------------------------
# Check if this is the leader node - restoration should ideally be performed on the leader
if [ "$ha_mode_before" != "active" ]; then
    log "${YELLOW}WARNING: This node is not the active (leader) node. Restoring on a non-leader node may cause issues.${NC}"
    log "It is recommended to run this script on the leader node for proper cluster restoration."
    read -p "Continue anyway? (y/n): " continue_nonleader
    if [[ ! "$continue_nonleader" =~ ^[Yy] ]]; then
        log "Restoration cancelled by user. Please run this on the leader node."
        exit 0
    fi
fi

# ----------------------------------------------------------------------------
# Raft peer information for reference
# ----------------------------------------------------------------------------
# Display current Raft peers to help identify the leader
log "Listing Raft peers to identify the leader..."
echo -e "\n${BLUE}Current Raft Peer Information:${NC}"
vault operator raft list-peers 2>/dev/null

# ----------------------------------------------------------------------------
# Snapshot selection and validation
# ----------------------------------------------------------------------------
# Find available snapshots and sort by date (newest first)
snapshots=($(find "$SNAPSHOT_DIR" -name "vault-raft-snapshot-*.snap" -type f | sort -r))
snapshot_count=${#snapshots[@]}

if [ $snapshot_count -eq 0 ]; then
    log "${RED}ERROR: No snapshots found in $SNAPSHOT_DIR.${NC}"
    log "Ensure the snapshot directory is correct and contains valid snapshots."
    exit 1
fi

log "${BLUE}=== Vault Raft Snapshot Restoration ===${NC}"
log "Found $snapshot_count snapshots in $SNAPSHOT_DIR"

# Display available snapshots with metadata for selection
log "${BLUE}Available snapshots:${NC}"
for i in "${!snapshots[@]}"; do
    filename=$(basename "${snapshots[$i]}")
    filesize=$(du -h "${snapshots[$i]}" | cut -f1)
    timestamp=$(stat -c %y "${snapshots[$i]}" | cut -d. -f1)
    echo "[$i] $filename ($filesize) - created $timestamp"
done

# Let user select which snapshot to restore
read -p "Enter the number of the snapshot to restore [0 for most recent]: " snapshot_num
snapshot_num=${snapshot_num:-0}

# Validate the selection
if ! [[ "$snapshot_num" =~ ^[0-9]+$ ]] || [ "$snapshot_num" -ge $snapshot_count ]; then
    log "${RED}Invalid selection. Using most recent snapshot.${NC}"
    snapshot_num=0
fi

selected_snapshot="${snapshots[$snapshot_num]}"
snapshot_name=$(basename "$selected_snapshot")
log "${GREEN}Selected snapshot: $snapshot_name${NC}"

# ----------------------------------------------------------------------------
# Multi-stage confirmation process
# ----------------------------------------------------------------------------
# First warning about data loss
echo ""
echo -e "${YELLOW}WARNING: This operation will REPLACE ALL VAULT DATA with the contents of the selected snapshot.${NC}"
echo "All tokens, leases, and secrets created after this snapshot was taken will be LOST."
echo ""

# Final confirmation requiring specific input to prevent accidental execution
echo -e "${RED}THIS IS A CRITICAL OPERATION THAT CANNOT BE UNDONE.${NC}"
read -p "Type 'RESTORE' in all caps to confirm you want to proceed: " final_confirm
if [ "$final_confirm" != "RESTORE" ]; then
    log "Restoration cancelled by user."
    exit 0
fi

# ----------------------------------------------------------------------------
# Snapshot restoration execution
# ----------------------------------------------------------------------------
log "Restoring from snapshot: $selected_snapshot"
# Capture both output and return code for error handling
restore_output=$(vault operator raft snapshot restore "$selected_snapshot" 2>&1)
restore_result=$?

if [ $restore_result -ne 0 ]; then
    log "${RED}ERROR: Snapshot restoration failed:${NC}"
    log "$restore_output"
    log "Check that your token has sufficient permissions (requires 'operator/raft' capabilities)."
    exit 1
fi

log "Snapshot restoration command completed successfully."

# ----------------------------------------------------------------------------
# Post-restoration verification
# ----------------------------------------------------------------------------
# Allow time for Vault to process the changes
log "Waiting for Vault to process the restoration..."
sleep 5

# Check updated Vault status
log "Checking Vault status after restoration..."
vault_status_after=$(vault status -format=json 2>/dev/null)
if [ $? -ne 0 ]; then
    log "${RED}ERROR: Unable to get Vault status after restoration. Manual verification required.${NC}"
    exit 1
fi

# Extract key metrics after restoration to verify changes
raft_applied_index_after=$(echo "$vault_status_after" | jq -r '.raft_applied_index // "unknown"')
ha_mode_after=$(echo "$vault_status_after" | jq -r '.ha_mode // "unknown"')

log "Vault Status After Restoration:"
log "- HA Mode: $ha_mode_after"
log "- Raft Applied Index: $raft_applied_index_after"

# ----------------------------------------------------------------------------
# Verification of successful restoration
# ----------------------------------------------------------------------------
# Compare Raft Applied Index to verify data was changed
if [ "$raft_applied_index_before" != "unknown" ] && [ "$raft_applied_index_after" != "unknown" ]; then
    if [ "$raft_applied_index_after" != "$raft_applied_index_before" ]; then
        log "${GREEN}Verification successful: Raft Applied Index has changed from $raft_applied_index_before to $raft_applied_index_after${NC}"
    else
        log "${YELLOW}WARNING: Raft Applied Index has not changed. This might indicate the restore did not apply new data.${NC}"
    fi
fi

# Check if Vault needs unsealing after restoration
is_sealed=$(echo "$vault_status_after" | jq -r '.sealed // "unknown"')
if [ "$is_sealed" == "true" ]; then
    log "${RED}WARNING: Vault is sealed after restoration. Manual unseal may be required.${NC}"
else
    log "${GREEN}Vault is unsealed and operational.${NC}"
fi

# ----------------------------------------------------------------------------
# Raft peer verification
# ----------------------------------------------------------------------------
# Verify Raft peer configuration after restoration
log "Confirming Raft members..."
echo -e "\n${BLUE}Raft Peer Information After Restoration:${NC}"
vault operator raft list-peers 2>/dev/null

# ----------------------------------------------------------------------------
# Restoration completion and next steps
# ----------------------------------------------------------------------------
log "${GREEN}Vault has been successfully restored from snapshot!${NC}"
log "Important: All clients may need to re-authenticate."
log "Any tokens or leases created after this snapshot was taken are now invalid."

echo ""
log "${GREEN}=== Restoration Complete ===${NC}"
log "Vault has been restored to the state captured in: $snapshot_name"
log "Check the logs at $LOG_FILE for detailed information."
echo ""
echo "Next steps:"
echo "1. Perform relevant tests to confirm desired data and configurations are present"
echo "2. Confirm KV entries are present"
echo "3. Test authentication methods like OIDC, LDAP, etc."
echo "4. For a clustered environment, verify all nodes are properly joined"
exit 0 