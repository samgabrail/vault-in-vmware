#!/bin/bash
# Vault Raft Autopilot Configuration Script
# This script configures Vault's Raft autopilot settings for dead server cleanup
# Should be run by the Vault Administrator

# Configuration variables - modify as needed
LOG_FILE="/var/log/vault-autopilot.log"

# Default autopilot settings - can be modified
CLEANUP_DEAD_SERVERS="true"
DEAD_SERVER_LAST_CONTACT_THRESHOLD="10"
MIN_QUORUM="3"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Ensure the log file exists and has proper permissions
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    log "Initialized autopilot configuration log file"
fi

# Check for vault binary
if ! command -v vault &> /dev/null; then
    log "${RED}ERROR: Vault CLI not found. Please install Vault or add it to PATH.${NC}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    log "${RED}ERROR: jq is not installed. It's required for parsing Vault responses.${NC}"
    exit 1
fi

# Ask for Vault address if not set
if [ -z "$VAULT_ADDR" ]; then
    DEFAULT_VAULT_ADDR="http://127.0.0.1:8200"
    read -p "Enter Vault server address [$DEFAULT_VAULT_ADDR]: " input_addr
    VAULT_ADDR=${input_addr:-$DEFAULT_VAULT_ADDR}
fi
export VAULT_ADDR
log "Using Vault address: $VAULT_ADDR"

# Authenticate to Vault if not already authenticated
if [ -z "$VAULT_TOKEN" ]; then
    echo -e "\n${BLUE}Select authentication method:${NC}"
    echo "1. Token (direct entry)"
    echo "2. Token (from file)"
    echo "3. LDAP"
    read -p "Choice [1]: " auth_method
    auth_method=${auth_method:-1}
    
    case $auth_method in
        1)
            echo "Please authenticate to Vault with your token:"
            vault login
            ;;
        2)
            read -p "Enter path to token file [/etc/vault/vault-token]: " token_file
            token_file=${token_file:-"/etc/vault/vault-token"}
            
            if [ -f "$token_file" ]; then
                VAULT_TOKEN=$(cat "$token_file")
                export VAULT_TOKEN
                log "Using token from $token_file"
                
                # Verify token works
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
            read -p "Enter LDAP username: " ldap_username
            echo "You will be prompted for your LDAP password next (input will not be displayed)"
            if ! vault login -method=ldap username="$ldap_username"; then
                log "${RED}ERROR: LDAP authentication failed.${NC}"
                exit 1
            fi
            ;;
        *)
            log "${RED}Invalid choice. Defaulting to token authentication.${NC}"
            vault login
            ;;
    esac
fi

# Verify Vault is running and we have access
log "Verifying Vault server is accessible..."
if ! vault status &> /dev/null; then
    log "${RED}ERROR: Vault server is not running or not accessible at $VAULT_ADDR.${NC}"
    exit 1
fi
log "${GREEN}Vault server is accessible.${NC}"

# Interactive configuration
echo -e "\n${BLUE}=== Vault Raft Autopilot Configuration ===${NC}"
echo "This script will configure Vault's Raft autopilot settings."
echo "These settings are critical for automated management of Raft servers,"
echo "especially in auto-scaling environments."
echo ""

read -p "Enable dead server cleanup? (true/false) [$CLEANUP_DEAD_SERVERS]: " input
CLEANUP_DEAD_SERVERS=${input:-$CLEANUP_DEAD_SERVERS}

read -p "Dead server last contact threshold in seconds [$DEAD_SERVER_LAST_CONTACT_THRESHOLD]: " input
DEAD_SERVER_LAST_CONTACT_THRESHOLD=${input:-$DEAD_SERVER_LAST_CONTACT_THRESHOLD}

read -p "Minimum quorum value [$MIN_QUORUM]: " input
MIN_QUORUM=${input:-$MIN_QUORUM}

# Apply configuration
log "Applying Raft autopilot configuration..."
log "- Cleanup dead servers: $CLEANUP_DEAD_SERVERS"
log "- Dead server last contact threshold: $DEAD_SERVER_LAST_CONTACT_THRESHOLD seconds"
log "- Minimum quorum: $MIN_QUORUM servers"

if vault operator raft autopilot set-config \
    -cleanup-dead-servers="$CLEANUP_DEAD_SERVERS" \
    -dead-server-last-contact-threshold="$DEAD_SERVER_LAST_CONTACT_THRESHOLD" \
    -min-quorum="$MIN_QUORUM"; then
    
    log "${GREEN}Autopilot configuration applied successfully.${NC}"
else
    log "${RED}ERROR: Failed to apply autopilot configuration.${NC}"
    exit 1
fi

# Verify configuration
log "Verifying autopilot configuration..."
echo -e "\n${BLUE}Current Autopilot Configuration:${NC}"
vault operator raft autopilot get-config

log "Vault Raft autopilot configuration completed successfully."
echo -e "\n${GREEN}Configuration complete!${NC}"
echo "The autopilot settings will help maintain cluster stability by"
echo "automatically removing dead servers from the Raft configuration."
echo ""
echo "For more information, see the Vault documentation on Raft Autopilot:"
echo "https://www.vaultproject.io/docs/concepts/integrated-storage/autopilot"
exit 0 