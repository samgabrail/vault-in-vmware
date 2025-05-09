#!/bin/bash
##############################################################################
# Vault Raft Autopilot Configuration Script
#
# PURPOSE:
# This script configures Vault's Raft Autopilot feature, which provides automatic
# management of server membership in the Raft cluster, particularly handling dead
# server removal, server stabilization, and voting weight management.
#
# CONTEXT:
# In a Raft-based Vault cluster, nodes can fail or become unreachable. Autopilot
# provides automatic failure detection and dead server cleanup, which is essential
# for maintaining cluster health without manual intervention.
#
# AUTOPILOT FEATURES:
# - Dead server cleanup: Automatically removes failed servers from the cluster
# - Server stabilization: Ensures servers are stable before promoting to voters
# - Redundancy zones: Distributes servers across redundancy zones
# - Upgrade migrations: Enables seamless cluster upgrades
#
# WORKFLOW:
# 1. Validates environment and dependencies
# 2. Authenticates to Vault
# 3. Configures Autopilot parameters through interactive prompts
# 4. Applies and verifies the configuration
#
# RECOMMENDED USAGE:
# Run this script after setting up a new Vault cluster or when you need to 
# adjust the Autopilot configuration for your environment.
##############################################################################

# ----------------------------------------------------------------------------
# Configuration variables - modify as appropriate for your environment
# ----------------------------------------------------------------------------
LOG_FILE="/var/log/vault-autopilot.log"  # Path for logging configuration actions

# Default autopilot settings - these can be overridden during interactive setup
CLEANUP_DEAD_SERVERS="true"                # Whether to remove dead servers automatically
DEAD_SERVER_LAST_CONTACT_THRESHOLD="10"    # Seconds before a server is considered dead
MIN_QUORUM="3"                            # Minimum servers needed for quorum

# ANSI color codes for better terminal output readability
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# ----------------------------------------------------------------------------
# Logging function to maintain a record of configuration changes
# ----------------------------------------------------------------------------
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
    echo -e "[$timestamp] $1"
}

# ----------------------------------------------------------------------------
# Environment setup and validation
# ----------------------------------------------------------------------------
# Ensure the log file exists with appropriate permissions
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"  # Secure permissions for log file
    log "Initialized autopilot configuration log file"
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
# Get Vault server address if not already set in environment
if [ -z "$VAULT_ADDR" ]; then
    DEFAULT_VAULT_ADDR="http://127.0.0.1:8200"
    read -p "Enter Vault server address [$DEFAULT_VAULT_ADDR]: " input_addr
    VAULT_ADDR=${input_addr:-$DEFAULT_VAULT_ADDR}
fi
export VAULT_ADDR  # Export for Vault CLI to use
log "Using Vault address: $VAULT_ADDR"

# ----------------------------------------------------------------------------
# Authentication to Vault - multiple methods supported
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
            # Direct token entry - prompts user to enter token
            echo "Please authenticate to Vault with your token:"
            vault login
            ;;
        2)
            # Read token from file - useful for automation
            read -p "Enter path to token file [/etc/vault/vault-token]: " token_file
            token_file=${token_file:-"/etc/vault/vault-token"}
            
            if [ -f "$token_file" ]; then
                VAULT_TOKEN=$(cat "$token_file")
                export VAULT_TOKEN
                log "Using token from $token_file"
                
                # Verify token is valid and has required permissions
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
            # LDAP authentication - requires LDAP auth method to be enabled
            read -p "Enter LDAP username: " ldap_username
            echo "You will be prompted for your LDAP password next (input will not be displayed)"
            if ! vault login -method=ldap username="$ldap_username"; then
                log "${RED}ERROR: LDAP authentication failed.${NC}"
                exit 1
            fi
            ;;
        *)
            # Default fallback for invalid entries
            log "${RED}Invalid choice. Defaulting to token authentication.${NC}"
            vault login
            ;;
    esac
fi

# ----------------------------------------------------------------------------
# Vault connectivity verification
# ----------------------------------------------------------------------------
log "Verifying Vault server is accessible..."
if ! vault status &> /dev/null; then
    log "${RED}ERROR: Vault server is not running or not accessible at $VAULT_ADDR.${NC}"
    log "Please check that Vault is running and the address is correct."
    exit 1
fi
log "${GREEN}Vault server is accessible.${NC}"

# ----------------------------------------------------------------------------
# Interactive configuration of Autopilot parameters
# ----------------------------------------------------------------------------
echo -e "\n${BLUE}=== Vault Raft Autopilot Configuration ===${NC}"
echo "This script will configure Vault's Raft autopilot settings."
echo "These settings are critical for automated management of Raft servers,"
echo "especially in auto-scaling environments."
echo ""

# Prompt for cleanup dead servers setting
read -p "Enable dead server cleanup? (true/false) [$CLEANUP_DEAD_SERVERS]: " input
CLEANUP_DEAD_SERVERS=${input:-$CLEANUP_DEAD_SERVERS}

# Prompt for dead server detection threshold
read -p "Dead server last contact threshold in seconds [$DEAD_SERVER_LAST_CONTACT_THRESHOLD]: " input
DEAD_SERVER_LAST_CONTACT_THRESHOLD=${input:-$DEAD_SERVER_LAST_CONTACT_THRESHOLD}

# Prompt for minimum quorum value
read -p "Minimum quorum value [$MIN_QUORUM]: " input
MIN_QUORUM=${input:-$MIN_QUORUM}

# ----------------------------------------------------------------------------
# Apply Autopilot configuration to Vault
# ----------------------------------------------------------------------------
log "Applying Raft autopilot configuration..."
log "- Cleanup dead servers: $CLEANUP_DEAD_SERVERS"
log "- Dead server last contact threshold: $DEAD_SERVER_LAST_CONTACT_THRESHOLD seconds"
log "- Minimum quorum: $MIN_QUORUM servers"

# Execute the Vault command to set Autopilot configuration
if vault operator raft autopilot set-config \
    -cleanup-dead-servers="$CLEANUP_DEAD_SERVERS" \
    -dead-server-last-contact-threshold="$DEAD_SERVER_LAST_CONTACT_THRESHOLD" \
    -min-quorum="$MIN_QUORUM"; then
    
    log "${GREEN}Autopilot configuration applied successfully.${NC}"
else
    log "${RED}ERROR: Failed to apply autopilot configuration.${NC}"
    log "Check that your token has sufficient permissions (requires 'operator/raft' capabilities)."
    exit 1
fi

# ----------------------------------------------------------------------------
# Verification and summary
# ----------------------------------------------------------------------------
# Display the current configuration to verify changes were applied
log "Verifying autopilot configuration..."
echo -e "\n${BLUE}Current Autopilot Configuration:${NC}"
vault operator raft autopilot get-config

# Provide summary and completion message
log "Vault Raft autopilot configuration completed successfully."
echo -e "\n${GREEN}Configuration complete!${NC}"
echo "The autopilot settings will help maintain cluster stability by"
echo "automatically removing dead servers from the Raft configuration."
echo ""
echo "For more information, see the Vault documentation on Raft Autopilot:"
echo "https://www.vaultproject.io/docs/concepts/integrated-storage/autopilot"
exit 0 