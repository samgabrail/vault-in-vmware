#!/bin/bash
# Vault Audit Logs Configuration Script
# This script enables and configures Vault audit logs
# Should be run by the Vault Administrator

# Configuration variables - modify as needed
LOG_FILE="/var/log/vault-audit-setup.log"
DEFAULT_AUDIT_LOG_PATH="/var/log/vault/audit.log"

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
    log "Initialized audit setup log file"
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
echo -e "\n${BLUE}=== Vault Audit Logs Configuration ===${NC}"
echo "This script will enable Vault audit logging."
echo "Audit logs are critical for security and compliance."
echo ""
echo -e "${YELLOW}NOTE: Vault requires at least one audit device to be enabled.${NC}"
echo "If all audit devices become unavailable, Vault will seal itself."
echo "For production, it's recommended to enable multiple audit devices."
echo ""

# Select audit device type
echo -e "${BLUE}Select the audit device type:${NC}"
echo "1. File audit device (recommended)"
echo "2. Syslog audit device"
echo "3. Socket audit device"
read -p "Choice [1]: " audit_type
audit_type=${audit_type:-1}

case $audit_type in
    1)
        device_type="file"
        device_description="File Audit Device"
        ;;
    2)
        device_type="syslog"
        device_description="Syslog Audit Device"
        ;;
    3)
        device_type="socket"
        device_description="Socket Audit Device"
        ;;
    *)
        device_type="file"
        device_description="File Audit Device"
        ;;
esac

# Configure audit device based on type
log "Configuring $device_description..."

if [ "$device_type" == "file" ]; then
    # File audit device configuration
    echo -e "${BLUE}File Audit Device Configuration:${NC}"
    read -p "Audit log file path [$DEFAULT_AUDIT_LOG_PATH]: " audit_log_path
    audit_log_path=${audit_log_path:-$DEFAULT_AUDIT_LOG_PATH}
    
    # Ensure the audit log directory exists
    audit_log_dir=$(dirname "$audit_log_path")
    if [ ! -d "$audit_log_dir" ]; then
        log "Creating audit log directory: $audit_log_dir"
        mkdir -p "$audit_log_dir"
        chmod 755 "$audit_log_dir"
    fi
    
    read -p "Log format (json/jsonx) [json]: " log_format
    log_format=${log_format:-json}
    
    read -p "Enable log rotation? (true/false) [true]: " log_raw
    log_raw=${log_raw:-true}
    
    # File device configuration
    log "Enabling file audit device at $audit_log_path..."
    if vault audit enable file file_path="$audit_log_path" format="$log_format" log_raw="$log_raw"; then
        log "${GREEN}File audit device enabled successfully.${NC}"
    else
        log "${RED}ERROR: Failed to enable file audit device.${NC}"
        exit 1
    fi
    
elif [ "$device_type" == "syslog" ]; then
    # Syslog audit device configuration
    echo -e "${BLUE}Syslog Audit Device Configuration:${NC}"
    read -p "Syslog tag [vault-audit]: " syslog_tag
    syslog_tag=${syslog_tag:-vault-audit}
    
    read -p "Syslog facility [AUTH]: " syslog_facility
    syslog_facility=${syslog_facility:-AUTH}
    
    # Syslog device configuration
    log "Enabling syslog audit device with tag $syslog_tag..."
    if vault audit enable syslog tag="$syslog_tag" facility="$syslog_facility"; then
        log "${GREEN}Syslog audit device enabled successfully.${NC}"
    else
        log "${RED}ERROR: Failed to enable syslog audit device.${NC}"
        exit 1
    fi
    
elif [ "$device_type" == "socket" ]; then
    # Socket audit device configuration
    echo -e "${BLUE}Socket Audit Device Configuration:${NC}"
    read -p "Socket address [127.0.0.1:9090]: " socket_address
    socket_address=${socket_address:-127.0.0.1:9090}
    
    read -p "Socket type (tcp/udp) [tcp]: " socket_type
    socket_type=${socket_type:-tcp}
    
    # Socket device configuration
    log "Enabling socket audit device to $socket_address..."
    if vault audit enable socket address="$socket_address" socket_type="$socket_type"; then
        log "${GREEN}Socket audit device enabled successfully.${NC}"
    else
        log "${RED}ERROR: Failed to enable socket audit device.${NC}"
        exit 1
    fi
fi

# List enabled audit devices
log "Listing enabled audit devices..."
echo -e "\n${BLUE}Enabled Audit Devices:${NC}"
vault audit list

log "Vault audit log configuration completed successfully."
echo -e "\n${GREEN}Audit logging has been enabled!${NC}"
echo "Audit logs are critical for security and compliance purposes."
echo "They provide a complete record of all requests and responses to Vault."
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} Ensure you have monitoring in place for audit log storage."
echo "If all audit devices become unavailable, Vault will seal itself."
echo ""
echo "For more information on Vault audit devices, see:"
echo "https://www.vaultproject.io/docs/audit"
exit 0 