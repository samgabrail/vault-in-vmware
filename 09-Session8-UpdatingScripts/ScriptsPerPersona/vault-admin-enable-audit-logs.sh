#!/bin/bash
# Vault Audit Logs Configuration Script
# This script enables and configures Vault audit logs and monitoring
# Should be run by the Vault Administrator

# Configuration variables - modify as needed
LOG_FILE="/var/log/vault-audit-setup.log"
AUDIT_LOG_PATH="/var/log/vault-audit.log"  # Standardized path for audit logs
OPERATIONAL_LOG_PATH="/var/log/vault.log"  # Standardized path for operational logs
DEFAULT_VAULT_ENV="dev"  # Default environment for DataDog tags

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
    log "Installing jq..."
    apt-get update && apt-get install -y jq || {
        log "${RED}Failed to install jq. Please install it manually.${NC}"
        exit 1
    }
fi

# Check if logrotate is installed
if ! command -v logrotate &> /dev/null; then
    log "${RED}WARNING: logrotate is not installed. It's required for log rotation.${NC}"
    log "Installing logrotate..."
    apt-get update && apt-get install -y logrotate || {
        log "${RED}Failed to install logrotate. Please install it manually.${NC}"
        exit 1
    }
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
echo "This script will enable Vault audit logging and monitoring."
echo "Audit logs are critical for security and compliance."
echo ""
echo -e "${YELLOW}NOTE: Vault requires at least one audit device to be enabled.${NC}"
echo "If all audit devices become unavailable, Vault will seal itself."
echo "For production, it's recommended to enable multiple audit devices."
echo ""

# Set up log files and permissions
echo -e "\n${BLUE}Setting up log files...${NC}"
log "Creating audit log file at $AUDIT_LOG_PATH"
touch "$AUDIT_LOG_PATH"
chmod 644 "$AUDIT_LOG_PATH"
if getent group vault > /dev/null 2>&1; then
    chown vault:vault "$AUDIT_LOG_PATH"
    log "Set ownership of audit log file to vault:vault"
else
    log "${YELLOW}WARNING: vault group not found. Setting default permissions.${NC}"
fi

log "Creating operational log file at $OPERATIONAL_LOG_PATH"
touch "$OPERATIONAL_LOG_PATH"
chmod 644 "$OPERATIONAL_LOG_PATH"
if getent group vault > /dev/null 2>&1; then
    chown vault:vault "$OPERATIONAL_LOG_PATH"
    log "Set ownership of operational log file to vault:vault"
fi

# Configure logrotate for audit logs
echo -e "\n${BLUE}Configuring logrotate for Vault logs...${NC}"
cat > /etc/logrotate.d/vault-audit.log << EOF
$AUDIT_LOG_PATH {
    rotate 7
    daily
    size 1G
    #Do not execute rotate if the log file is empty.
    notifempty
    missingok
    compress
    #Set compress on next rotate cycle to prevent entry loss when performing compression.
    delaycompress
    copytruncate
    extension log
    dateext
    dateformat %Y-%m-%d.
}
EOF
log "Created logrotate configuration for audit logs"

# Configure logrotate for operational logs
cat > /etc/logrotate.d/vault.log << EOF
$OPERATIONAL_LOG_PATH {
    rotate 7
    daily
    size 1G
    #Do not execute rotate if the log file is empty.
    notifempty
    missingok
    compress
    #Set compress on next rotate cycle to prevent entry loss when performing compression.
    delaycompress
    copytruncate
    extension log
    dateext
    dateformat %Y-%m-%d.
}
EOF
log "Created logrotate configuration for operational logs"

# Modify systemd service file to redirect output to operational log
if [ -f "/lib/systemd/system/vault.service" ]; then
    echo -e "\n${BLUE}Updating Vault service to log operations...${NC}"
    
    # Check if modifications are already present
    if ! grep -q "StandardOutput=append:$OPERATIONAL_LOG_PATH" /lib/systemd/system/vault.service; then
        # Add log level and redirect output
        sed -i "s|^ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl$|ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl -log-level=\"trace\"|" /lib/systemd/system/vault.service
        sed -i "/^\[Service\]$/a StandardOutput=append:$OPERATIONAL_LOG_PATH\nStandardError=append:$OPERATIONAL_LOG_PATH" /lib/systemd/system/vault.service
        
        # Get Vault version for DataDog tagging
        VAULT_VERSION=$(vault version | awk '{print $2}' | sed 's/v//')
        
        # Ask for environment tag
        read -p "Enter environment tag for monitoring (prod/stage/dev) [$DEFAULT_VAULT_ENV]: " vault_env
        vault_env=${vault_env:-$DEFAULT_VAULT_ENV}
        
        # Add DataDog environment variables
        sed -i "/^\[Service\]/a Environment=DD_ENV=$vault_env\nEnvironment=DD_SERVICE=vault\nEnvironment=DD_VERSION=$VAULT_VERSION" /lib/systemd/system/vault.service
        
        log "Updated vault.service with logging and monitoring configurations"
        log "Reloading systemd daemon"
        systemctl daemon-reload
        
        echo -e "\n${YELLOW}NOTE:${NC} You need to restart Vault for operational logging changes to take effect:"
        echo "systemctl restart vault"
    else
        log "Vault service file already configured for logging"
    fi
else
    log "${YELLOW}WARNING: Vault systemd service file not found. Skipping operational logging setup.${NC}"
fi

# DataDog monitoring setup placeholder
echo -e "\n${BLUE}DataDog monitoring configuration${NC}"
echo "To enable DataDog monitoring, please follow these steps:"
echo "1. Install the DataDog agent:"
echo "   DD_AGENT_MAJOR_VERSION=7 DD_API_KEY=<your_api_key> bash -c \\"
echo "   \"\$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh)\""
echo ""
echo "2. Create the DataDog Vault configuration:"
echo "   mkdir -p /etc/datadog-agent/conf.d/vault.d/"
echo "   Create file: /etc/datadog-agent/conf.d/vault.d/conf.yaml with contents:"
echo ""
cat << 'EOF'
init_config:
instances:
  - use_openmetrics: true
    api_url: https://127.0.0.1:8200/v1
    no_token: true
    tls_verify: true
    tls_cert: /opt/vault/tls/vault-cert.pem
    tls_private_key: /opt/vault/tls/vault-key.pem
    tls_ca_cert: /opt/vault/tls/vault-ca.pem
logs:
  - type: file
    path: /var/log/vault-audit.log
    source: vault
  - type: file
    path: /var/log/vault.log
    source: vault
EOF
echo ""
echo "3. Enable logs collection in DataDog:"
echo "   sed -i 's/#\\s*logs_enabled:\\s*false/logs_enabled: true/' /etc/datadog-agent/datadog.yaml"
echo ""
echo "4. Give DataDog agent access to Vault logs:"
echo "   usermod -a -G vault dd-agent"
echo ""
echo "5. Restart the DataDog agent:"
echo "   systemctl restart datadog-agent"

# Select audit device type
echo -e "\n${BLUE}Select the audit device type:${NC}"
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
    read -p "Use standard audit log path? ($AUDIT_LOG_PATH) [Y/n]: " use_standard_path
    if [[ "$use_standard_path" =~ ^[Nn]$ ]]; then
        read -p "Enter custom audit log path: " audit_log_path
    else
        audit_log_path=$AUDIT_LOG_PATH
    fi
    
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
echo "Audit logs are stored at: $AUDIT_LOG_PATH"
echo "Operational logs are stored at: $OPERATIONAL_LOG_PATH"
echo "Log rotation has been configured for both log types."
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} Ensure you have monitoring in place for audit log storage."
echo "If all audit devices become unavailable, Vault will seal itself."
echo ""
echo "For more information, see:"
echo "- Vault Audit Devices: https://www.vaultproject.io/docs/audit"
echo "- DataDog Integration: https://docs.datadoghq.com/integrations/vault/"
exit 0 