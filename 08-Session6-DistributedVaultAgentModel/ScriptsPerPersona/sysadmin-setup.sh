#!/bin/bash
# System Administrator Setup Script
# This script is used by SysAdmins to:
# 1. Create the necessary users and directories
# 2. Set up Vault Agent configurations
# 3. Create systemd service files
# 4. Set appropriate permissions

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Define file naming conventions
VAULT_DATA_DIR="/etc/vault-agents"
APP_DATA_DIR_FORMAT="$VAULT_DATA_DIR/%s"
ROLE_ID_FILE_FORMAT="$VAULT_DATA_DIR/%s/role-id"
WRAPPED_SECRET_ID_FILE_FORMAT="$VAULT_DATA_DIR/%s/wrapped-secret-id"
TOKEN_SINK_DIR="/home/springApps/.vault-tokens"
SCRIPT_PATH_FORMAT="/home/springApps/scripts/%s-script.py"
VAULTAGENT_USER="vaultagent"
APPS_USER="springApps"
REFRESH_SCRIPT="$VAULT_DATA_DIR/refresh-secret-ids.sh"
CRON_FILE="/etc/cron.d/vault-agent-renewal"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: This script must be run as root (required for systemd operations).${NC}"
  echo "Please run with sudo or as root user."
  exit 1
fi

echo -e "\n${BLUE}=== System Administrator Setup ===${NC}"
echo "This script will set up Vault Agent services and necessary file permissions."

# Determine if this is an initial setup or adding new applications
if [ -d "$VAULT_DATA_DIR" ] && [ -f "$VAULT_DATA_DIR/restart-role-id" ]; then
    echo -e "\n${GREEN}Existing Vault Agent setup detected.${NC}"
    initial_setup=false
    
    # Ask if they want to add new apps or do a full setup
    echo -e "\n${BLUE}What would you like to do?${NC}"
    echo "1. Add new applications to existing setup"
    echo "2. Perform complete setup (will preserve existing restart credentials)"
    read -p "Choice [1]: " setup_choice
    setup_choice=${setup_choice:-1}
    
    if [ "$setup_choice" == "2" ]; then
        echo "Performing complete setup while preserving restart credentials..."
        initial_setup=true
    else
        echo "Adding new applications to existing setup..."
    fi
else
    echo -e "\n${GREEN}No existing setup detected. Performing initial setup.${NC}"
    initial_setup=true
fi

# Only ask for restart AppRole credentials during initial setup
if [ "$initial_setup" = true ]; then
    # Get restart AppRole credentials
    echo -e "\n${GREEN}Restart AppRole Credentials${NC}"
    echo "These credentials are provided by the Vault Admin (IT Security)."
    echo "They are needed to authenticate and fetch application-specific credentials."
    
    RESTART_ROLE_ID=""
    RESTART_SECRET_ID=""
    
    # Option to use a JSON credentials file
    echo -e "\n${BLUE}Please select how you want to enter the restart AppRole credentials:${NC}"
    echo "1. Enter credentials manually"
    echo "2. Load from JSON file"
    read -p "Option [1]: " credentials_option
    credentials_option=${credentials_option:-1}
    
    if [ "$credentials_option" = "2" ]; then
        read -p "Enter path to the JSON credentials file: " json_path
        if [ -f "$json_path" ]; then
            RESTART_ROLE_ID=$(jq -r '.role_id' "$json_path")
            RESTART_SECRET_ID=$(jq -r '.secret_id' "$json_path")
        else
            echo -e "${RED}Error: File not found. Falling back to manual entry.${NC}"
            credentials_option=1
        fi
    fi
    
    if [ "$credentials_option" = "1" ]; then
        read -p "Enter the Restart Role ID: " RESTART_ROLE_ID
        read -p "Enter the Restart Secret ID: " RESTART_SECRET_ID
    fi
    
    if [ -z "$RESTART_ROLE_ID" ] || [ -z "$RESTART_SECRET_ID" ]; then
        echo -e "${RED}Error: Restart AppRole credentials are required.${NC}"
        exit 1
    fi
else
    # Read existing restart AppRole credentials
    if [ -f "$VAULT_DATA_DIR/restart-role-id" ] && [ -f "$VAULT_DATA_DIR/restart-secret-id" ]; then
        RESTART_ROLE_ID=$(cat "$VAULT_DATA_DIR/restart-role-id")
        RESTART_SECRET_ID=$(cat "$VAULT_DATA_DIR/restart-secret-id")
        echo -e "${GREEN}Using existing restart AppRole credentials.${NC}"
    else
        echo -e "${RED}Error: Existing restart AppRole credentials not found.${NC}"
        echo "Please run a complete setup with new credentials."
        exit 1
    fi
fi

# Get list of applications to set up
echo -e "\n${GREEN}Application Configuration${NC}"
read -p "Enter application names (space-separated): " APP_NAMES_INPUT
IFS=' ' read -r -a APP_NAMES <<< "$APP_NAMES_INPUT"

if [ ${#APP_NAMES[@]} -eq 0 ]; then
    echo "No applications specified. Using default examples: webapp database"
    APP_NAMES=("webapp" "database")
fi

# Get vault address
VAULT_ADDR=${VAULT_ADDR:-"http://127.0.0.1:8200"}
read -p "Enter Vault server address [$VAULT_ADDR]: " input
VAULT_ADDR=${input:-$VAULT_ADDR}

# Initial setup tasks
if [ "$initial_setup" = true ]; then
    echo -e "\n${GREEN}Creating dedicated users...${NC}"
    # Create vaultagent user for running Vault Agents if it doesn't exist
    if ! id -u $VAULTAGENT_USER &>/dev/null; then
        useradd -r -s /bin/false $VAULTAGENT_USER
        echo "Created $VAULTAGENT_USER user"
    else
        echo "User $VAULTAGENT_USER already exists"
    fi
    
    # Create a single user for all applications if it doesn't exist
    if ! id -u $APPS_USER &>/dev/null; then
        useradd -m -s /bin/bash $APPS_USER
        echo "Created user $APPS_USER with home directory /home/$APPS_USER"
    else
        echo "User $APPS_USER already exists"
    fi
    
    # Create scripts directory in user's home if it doesn't exist
    app_scripts_dir="/home/$APPS_USER/scripts"
    if [ ! -d "$app_scripts_dir" ]; then
        mkdir -p $app_scripts_dir
        chown $APPS_USER:$APPS_USER $app_scripts_dir
        chmod 755 $app_scripts_dir
        echo "Created scripts directory: $app_scripts_dir"
    else
        echo "Scripts directory already exists: $app_scripts_dir"
    fi
    
    # Create tokens directory in user's home if it doesn't exist
    if [ ! -d "$TOKEN_SINK_DIR" ]; then
        mkdir -p $TOKEN_SINK_DIR
        chown $VAULTAGENT_USER:$APPS_USER $TOKEN_SINK_DIR
        chmod 750 $TOKEN_SINK_DIR
        echo "Created token sink directory: $TOKEN_SINK_DIR"
    else
        echo "Token sink directory already exists: $TOKEN_SINK_DIR"
    fi
    
    # Create the data directory if it doesn't exist
    echo -e "\n${GREEN}Creating Vault Agent data directory...${NC}"
    if [ ! -d "$VAULT_DATA_DIR" ]; then
        mkdir -p $VAULT_DATA_DIR
        chmod 755 $VAULT_DATA_DIR
        # Set ownership to vaultagent instead of root
        chown $VAULTAGENT_USER:$VAULTAGENT_USER $VAULT_DATA_DIR
        echo "Created Vault Agent data directory: $VAULT_DATA_DIR"
    else
        echo "Vault Agent data directory already exists: $VAULT_DATA_DIR"
        # Update ownership to vaultagent for existing directory
        chown $VAULTAGENT_USER:$VAULTAGENT_USER $VAULT_DATA_DIR
    fi
    
    # Store the restart AppRole credentials if not already stored
    echo -e "\n${GREEN}Storing restart AppRole credentials...${NC}"
    echo "$RESTART_ROLE_ID" > $VAULT_DATA_DIR/restart-role-id
    echo "$RESTART_SECRET_ID" > $VAULT_DATA_DIR/restart-secret-id
    chmod 600 $VAULT_DATA_DIR/restart-role-id $VAULT_DATA_DIR/restart-secret-id
    chown $VAULTAGENT_USER:$VAULTAGENT_USER $VAULT_DATA_DIR/restart-role-id $VAULT_DATA_DIR/restart-secret-id
    echo "Stored restart AppRole credentials"
else
    # For non-initial setup, ensure directories exist
    for dir in "$VAULT_DATA_DIR" "$TOKEN_SINK_DIR" "/home/$APPS_USER/scripts"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            echo "Created directory: $dir"
        fi
    done
    
    # Ensure proper permissions on token sink dir
    chown $VAULTAGENT_USER:$APPS_USER $TOKEN_SINK_DIR
    chmod 750 $TOKEN_SINK_DIR
fi

echo -e "\n${GREEN}Creating application directories...${NC}"
# Create directories for each app
for app_name in "${APP_NAMES[@]}"; do
    app_dir=$(printf $APP_DATA_DIR_FORMAT $app_name)
    if [ ! -d "$app_dir" ]; then
        mkdir -p "$app_dir"
        # Allow vault agent to manage these directories
        chmod 750 "$app_dir"
        # Set ownership to vault agent
        chown $VAULTAGENT_USER:$VAULTAGENT_USER "$app_dir"
        echo "Created directory for $app_name: $app_dir"
    else
        echo "Directory for $app_name already exists: $app_dir"
    fi
done

echo -e "\n${GREEN}Creating the vault agent startup scripts...${NC}"
# Create a startup script for each app
for i in "${!APP_NAMES[@]}"; do
    app_name=${APP_NAMES[$i]}
    startup_script="$VAULT_DATA_DIR/${app_name}-agent-start.sh"
    
    # Check if the startup script already exists
    if [ -f "$startup_script" ]; then
        echo "Startup script for $app_name already exists, updating..."
    else
        echo "Creating startup script for $app_name..."
    fi
    
    cat > "$startup_script" << EOF
#!/bin/bash
# Startup script for Vault Agent for ${app_name}

export VAULT_ADDR='$VAULT_ADDR'
APP_DIR="$VAULT_DATA_DIR/${app_name}"

# Grab the restart approle creds from files
RESTART_ROLE_ID=\$(cat $VAULT_DATA_DIR/restart-role-id)
RESTART_SECRET_ID=\$(cat $VAULT_DATA_DIR/restart-secret-id)

# Authenticate to Vault with the restart AppRole creds
VAULT_TOKEN=\$(vault write -field=token auth/approle/login role_id=\$RESTART_ROLE_ID secret_id=\$RESTART_SECRET_ID)

if [ -z "\$VAULT_TOKEN" ]; then
    echo "Failed to authenticate with restart role"
    exit 1
fi

export VAULT_TOKEN

# Get the role ID for this application
vault read -field=role_id auth/approle/role/${app_name}/role-id > \$APP_DIR/role-id
chmod 600 \$APP_DIR/role-id

# Write a wrapped secret-id to the expected location
vault write -field=wrapping_token -wrap-ttl=200s -f auth/approle/role/${app_name}/secret-id > \$APP_DIR/wrapped-secret-id
chmod 600 \$APP_DIR/wrapped-secret-id

# Start the agent
exec vault agent -config=$VAULT_DATA_DIR/${app_name}-agent.hcl
EOF

    chmod 700 "$startup_script"
    chown $VAULTAGENT_USER:$VAULTAGENT_USER "$startup_script"
done

echo -e "\n${GREEN}Creating Vault Agent configurations...${NC}"
# Create Vault Agent configuration for each app
for i in "${!APP_NAMES[@]}"; do
    app_name=${APP_NAMES[$i]}
    token_path="$TOKEN_SINK_DIR/${app_name}-token"
    config_file="$VAULT_DATA_DIR/${app_name}-agent.hcl"
    
    # Check if the config file already exists
    if [ -f "$config_file" ]; then
        echo "Configuration file for $app_name already exists, updating..."
    else
        echo "Creating configuration file for $app_name..."
    fi
    
    cat > "$config_file" << EOF
exit_after_auth = false
pid_file = "$VAULT_DATA_DIR/${app_name}/vault-agent.pid"

vault {
  address = "$VAULT_ADDR"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "$(printf $ROLE_ID_FILE_FORMAT $app_name)"
      secret_id_file_path = "$(printf $WRAPPED_SECRET_ID_FILE_FORMAT $app_name)"
      remove_secret_id_file_after_reading = true
      secret_id_response_wrapping_path = "auth/approle/role/${app_name}/secret-id"
    }
  }

  sink "file" {
    config = {
      path = "${token_path}"
      mode = 0440
    }
  }
}
EOF

    chmod 640 "$config_file"
    chown $VAULTAGENT_USER:$VAULTAGENT_USER "$config_file"
done

echo -e "\n${GREEN}Creating systemd service files...${NC}"
# Create systemd service for each app
for app_name in "${APP_NAMES[@]}"; do
    service_file="/etc/systemd/system/vault-agent-${app_name}.service"
    
    # Check if the service file already exists
    if [ -f "$service_file" ]; then
        echo "Service file for $app_name already exists, updating..."
    else
        echo "Creating service file for $app_name..."
    fi
    
    cat > "$service_file" << EOF
[Unit]
Description=Vault Agent for ${app_name^}
After=network.target

[Service]
Type=simple
ExecStart=$VAULT_DATA_DIR/${app_name}-agent-start.sh
Restart=on-failure
RestartSec=10
User=$VAULTAGENT_USER
Group=$APPS_USER

[Install]
WantedBy=multi-user.target
EOF
done

# Create secret ID renewal script
echo -e "\n${GREEN}Creating Secret ID renewal script...${NC}"
# Check if the refresh script already exists
refresh_script_exists=false
if [ -f "$REFRESH_SCRIPT" ]; then
    refresh_script_exists=true
    echo "Secret ID renewal script already exists."
    echo -e "${BLUE}What would you like to do?${NC}"
    echo "1. Keep existing script"
    echo "2. Update script (will preserve any custom modifications)"
    echo "3. Recreate script (will overwrite any custom modifications)"
    read -p "Choice [1]: " refresh_script_choice
    refresh_script_choice=${refresh_script_choice:-1}
else
    # Script doesn't exist, create it
    refresh_script_choice=3
fi

# Only create or update script if user chose options 2 or 3
if [ "$refresh_script_choice" = "3" ]; then
    # Full recreation of script
    cat > "$REFRESH_SCRIPT" << 'EOF'
#!/bin/bash
# This script refreshes the secret IDs for all Vault Agents
# It should be run periodically via cron before the secret IDs expire

VAULT_DATA_DIR="/etc/vault-agents"
VAULT_ADDR="PLACEHOLDER_VAULT_ADDR"
LOG_FILE="/var/log/vault-agent-renewal.log"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Ensure the log file exists and has proper permissions
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"
chown vaultagent:vaultagent "$LOG_FILE"

log "Starting Vault Agent Secret ID renewal process"

# Set Vault address
export VAULT_ADDR

# Check if restart credentials exist
if [ ! -f "$VAULT_DATA_DIR/restart-role-id" ] || [ ! -f "$VAULT_DATA_DIR/restart-secret-id" ]; then
    log "ERROR: Restart AppRole credentials not found"
    exit 1
fi

# Get the restart role credentials
RESTART_ROLE_ID=$(cat "$VAULT_DATA_DIR/restart-role-id")
RESTART_SECRET_ID=$(cat "$VAULT_DATA_DIR/restart-secret-id")

# Authenticate with restart AppRole
log "Authenticating with restart AppRole"
VAULT_TOKEN=$(vault write -field=token auth/approle/login role_id="$RESTART_ROLE_ID" secret_id="$RESTART_SECRET_ID")

if [ -z "$VAULT_TOKEN" ]; then
    log "ERROR: Failed to authenticate with restart role"
    exit 1
fi

export VAULT_TOKEN

# Get list of application directories
app_dirs=$(find "$VAULT_DATA_DIR" -maxdepth 1 -type d -not -path "$VAULT_DATA_DIR" | sort)
app_count=0

for app_dir in $app_dirs; do
    app_name=$(basename "$app_dir")
    
    # Skip non-application directories
    if [[ "$app_name" == "." || "$app_name" == ".." ]]; then
        continue
    fi
    
    log "Processing application: $app_name"
    
    # Get the role ID first to ensure this is a valid app
    role_id_file="$VAULT_DATA_DIR/$app_name/role-id"
    if [ ! -f "$role_id_file" ]; then
        log "  No role-id file found for $app_name, creating one"
        # Get the role ID for this application
        vault read -field=role_id "auth/approle/role/$app_name/role-id" > "$role_id_file" 2>/dev/null
        
        if [ $? -ne 0 ]; then
            log "  ERROR: Failed to get role-id for $app_name, skipping"
            continue
        fi
        
        chmod 600 "$role_id_file"
        chown vaultagent:springApps "$role_id_file"
    fi
    
    # Generate a new wrapped secret ID
    log "  Generating new wrapped secret ID for $app_name"
    wrapped_secret_id_file="$VAULT_DATA_DIR/$app_name/wrapped-secret-id"
    
    # Write a wrapped secret-id to the expected location
    vault write -field=wrapping_token -wrap-ttl=200s -f "auth/approle/role/$app_name/secret-id" > "$wrapped_secret_id_file" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        log "  ERROR: Failed to generate wrapped secret ID for $app_name"
        continue
    fi
    
    chmod 600 "$wrapped_secret_id_file"
    chown vaultagent:springApps "$wrapped_secret_id_file"
    log "  Successfully renewed secret ID for $app_name"
    
    app_count=$((app_count+1))
done

log "Completed Vault Agent Secret ID renewal for $app_count applications"
EOF

    # Update the Vault address in the script
    sed -i "s|PLACEHOLDER_VAULT_ADDR|$VAULT_ADDR|g" "$REFRESH_SCRIPT"
    if ! $refresh_script_exists; then
        # Set permissions only if we're creating a new file
        chmod 700 "$REFRESH_SCRIPT"
        chown $VAULTAGENT_USER:$VAULTAGENT_USER "$REFRESH_SCRIPT"
    fi
    echo "Created/recreated Secret ID renewal script at $REFRESH_SCRIPT"

elif [ "$refresh_script_choice" = "2" ]; then
    # Update the Vault address in the existing script
    sed -i "s|VAULT_ADDR=.*|VAULT_ADDR=\"$VAULT_ADDR\"|g" "$REFRESH_SCRIPT"
    echo "Updated Vault address in existing Secret ID renewal script"
else
    echo "Keeping existing Secret ID renewal script"
fi

# Set up cronjob for regular renewal
echo -e "\n${GREEN}Setting up cron job for Secret ID renewal...${NC}"

# Ask how often to renew
echo -e "${BLUE}How often should Secret IDs be renewed?${NC}"
echo "IMPORTANT: Application Secret IDs expire after 24 hours as configured in the vault-admin-setup.sh script."
echo "The renewal job should run more frequently than this to ensure continuous operation."
echo "1. Every 8 hours (recommended for 24-hour TTL)"
echo "2. Every 12 hours (also good for 24-hour TTL)"
echo "3. Daily (cutting it close for 24-hour TTL)"
echo "4. Custom (specify cron expression)"
read -p "Choice [1]: " cron_choice
cron_choice=${cron_choice:-1}

case $cron_choice in
    1)
        cron_schedule="0 */8 * * *"  # Every 8 hours
        cron_description="every 8 hours"
        ;;
    2)
        cron_schedule="0 */12 * * *"  # Every 12 hours
        cron_description="every 12 hours"
        ;;
    3)
        cron_schedule="0 0 * * *"  # Every day at midnight
        cron_description="daily"
        echo -e "${RED}Warning: This is cutting it close with the 24-hour Secret ID TTL.${NC}"
        echo "If there are any issues with the renewal job, your applications may lose access."
        ;;
    4)
        read -p "Enter custom cron schedule (e.g., '0 */8 * * *' for every 8 hours): " cron_schedule
        cron_description="custom"
        echo "Make sure your schedule runs more frequently than the Secret ID TTL (24 hours by default)."
        ;;
    *)
        cron_schedule="0 */8 * * *"  # Default to every 8 hours
        cron_description="every 8 hours"
        ;;
esac

# Create the cron job
cat > "$CRON_FILE" << EOF
# Vault Agent Secret ID renewal - runs $cron_description
# Note: Application Secret IDs expire after 24 hours by default
$cron_schedule root $REFRESH_SCRIPT
EOF

chmod 644 "$CRON_FILE"
echo "Created cron job for $cron_description Secret ID renewal"

echo -e "\n${GREEN}Reloading systemd and enabling services...${NC}"
systemctl daemon-reload

# Enable services for new applications
for app_name in "${APP_NAMES[@]}"; do
    if ! systemctl is-enabled --quiet vault-agent-${app_name}.service &>/dev/null; then
        systemctl enable vault-agent-${app_name}.service
        echo "Enabled vault-agent-${app_name}.service"
    else
        echo "Service vault-agent-${app_name}.service already enabled"
    fi
done

# Ask if should start services now
echo -e "\n${BLUE}Do you want to start/restart the Vault Agent services now? (y/n)${NC}"
read -p "Start services [y]: " start_services
start_services=${start_services:-y}

if [[ "$start_services" =~ ^[Yy] ]]; then
    echo -e "\n${GREEN}Starting/Restarting Vault Agent services...${NC}"
    for app_name in "${APP_NAMES[@]}"; do
        # Check if service is already running
        if systemctl is-active --quiet vault-agent-${app_name}.service; then
            systemctl restart vault-agent-${app_name}.service
            echo "Restarted vault-agent-${app_name}.service"
        else
            systemctl start vault-agent-${app_name}.service
            echo "Started vault-agent-${app_name}.service"
        fi
    done

    # Wait for tokens to be created
    echo "Waiting for tokens to be created..."
    sleep 10

    # Script to monitor file and fix permissions
    echo -e "\n${GREEN}Setting up token permission monitoring...${NC}"
    
    # Check if tokens were created
    tokens_created=true
    for app_name in "${APP_NAMES[@]}"; do
        token_path="$TOKEN_SINK_DIR/${app_name}-token"
        if [ ! -f "$token_path" ]; then
            echo -e "${RED}Warning: Token for ${app_name} was not created.${NC}"
            echo "Check the service logs with: journalctl -u vault-agent-${app_name}.service"
            tokens_created=false
        else
            echo "Token for ${app_name} created successfully."
            
            # Fix token file permissions
            echo "Setting correct permissions on token file for $app_name"
            chmod 440 $token_path
            chown $VAULTAGENT_USER:$APPS_USER $token_path
            
            # Verify permissions after change
            owner_group=$(stat -c '%U:%G' $token_path)
            if [ "$owner_group" == "$VAULTAGENT_USER:$APPS_USER" ]; then
                echo -e "  ${GREEN}Permissions set correctly to $VAULTAGENT_USER:$APPS_USER${NC}"
            else
                echo -e "  ${RED}Failed to set permissions properly. Current ownership: $owner_group${NC}"
            fi
        fi
    done

    if [ "$tokens_created" = false ]; then
        echo -e "${RED}One or more tokens were not created. Check the logs for details.${NC}"
    else
        echo -e "${GREEN}All tokens created successfully!${NC}"
    fi
else
    echo "Services not started. You can start them later with:"
    for app_name in "${APP_NAMES[@]}"; do
        echo "  sudo systemctl start vault-agent-${app_name}.service"
    done
fi

# Function to check and fix token permissions for existing tokens
check_fix_token_permissions() {
    echo -e "\n${GREEN}Verifying existing token file permissions...${NC}"
    for app_name in "${APP_NAMES[@]}"; do
        token_path="$TOKEN_SINK_DIR/${app_name}-token"
        if [ -f "$token_path" ]; then
            owner=$(stat -c '%U' "$token_path")
            group=$(stat -c '%G' "$token_path")
            perms=$(stat -c '%a' "$token_path")
            
            echo -e "Token file for ${app_name}:"
            echo "  Path: $token_path"
            echo "  Current ownership: $owner:$group"
            echo "  Current permissions: $perms"
            
            if [ "$owner" != "$VAULTAGENT_USER" ] || [ "$group" != "$APPS_USER" ] || [ "$perms" != "440" ]; then
                echo -e "  ${RED}Incorrect permissions detected, fixing...${NC}"
                chown $VAULTAGENT_USER:$APPS_USER "$token_path"
                chmod 440 "$token_path"
                
                # Verify again after changes
                new_owner_group=$(stat -c '%U:%G' "$token_path")
                new_perms=$(stat -c '%a' "$token_path")
                echo -e "  ${GREEN}Updated to: $new_owner_group with mode $new_perms${NC}"
            else
                echo -e "  ${GREEN}Permissions are correct${NC}"
            fi
        fi
    done
}

# Check token permissions if we didn't start services
if [[ ! "$start_services" =~ ^[Yy] ]]; then
    check_fix_token_permissions
fi

# Generate information for DevOps
echo -e "\n${BLUE}==== APPLICATION INFORMATION FOR DEVOPS ====${NC}"
echo "Please share the following information with your DevOps team:"
echo ""

for i in "${!APP_NAMES[@]}"; do
    app_name=${APP_NAMES[$i]}
    
    echo -e "${GREEN}${app_name}:${NC}"
    echo "- Token Path: $TOKEN_SINK_DIR/${app_name}-token"
    echo ""
done

echo -e "\n${GREEN}System Administrator setup complete!${NC}"
echo "Summary:"
if [ "$initial_setup" = true ]; then
    echo "1. Created the necessary users and directories"
    echo "2. Stored the restart AppRole credentials securely"
fi
echo "3. Created/Updated Vault Agent configurations for each application"
echo "4. Set up systemd services for each Vault Agent"
echo "5. Set appropriate file permissions"
echo "6. Ensured token files have correct permissions (vaultagent:springApps with mode 440)"
echo "7. Created Secret ID renewal script and cron job for $cron_description renewals"
echo ""
echo "To check the status of the services:"
for app_name in "${APP_NAMES[@]}"; do
    echo "  sudo systemctl status vault-agent-${app_name}.service"
done
echo ""
echo "To view service logs:"
for app_name in "${APP_NAMES[@]}"; do
    echo "  sudo journalctl -u vault-agent-${app_name}.service"
done
echo ""
echo "Secret ID renewal:"
echo "  Script location: $REFRESH_SCRIPT"
echo "  Cron job: $cron_description ($cron_schedule)"
echo "  Log file: /var/log/vault-agent-renewal.log"
echo ""

# Cleanup instructions
echo -e "\n${BLUE}To clean up when you're done (not required now):${NC}"
echo "  sudo systemctl stop $(printf "vault-agent-%s " "${APP_NAMES[@]}")"
echo "  sudo systemctl disable $(printf "vault-agent-%s " "${APP_NAMES[@]}")"
echo "  sudo rm -f $(printf "/etc/systemd/system/vault-agent-%s.service " "${APP_NAMES[@]}")"
echo "  sudo rm -f $CRON_FILE"
echo "  sudo rm -rf $VAULT_DATA_DIR"
echo "  sudo systemctl daemon-reload"
echo "  sudo userdel $VAULTAGENT_USER"
echo "  sudo userdel -r $APPS_USER  # -r flag removes home directory"
echo "" 