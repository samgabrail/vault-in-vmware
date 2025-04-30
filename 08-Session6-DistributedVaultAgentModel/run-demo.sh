#!/bin/bash
# Enhanced Demo script for running separate Vault Agents for each application
# This version adds:
# 1. A dedicated restart AppRole with tight permissions
# 2. Wrapped secret-ids with TTL constraints for improved security
# 3. Systemd integration for Vault Agents
# 4. On-demand role-id and secret-id delivery
# 5. Support for arbitrary application names

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
TOKEN_SINK_FORMAT="$VAULT_DATA_DIR/%s/vault-token"
SCRIPT_PATH_FORMAT="$VAULT_DATA_DIR/%s-script.py"
VAULTAGENT_USER="vaultagent"
APP_USER="appuser"
APP_SCRIPTS_DIR="/home/$APP_USER/vault-scripts"

# List of applications to set up - MODIFY THIS LIST for your environment
declare -a APP_NAMES=("webapp" "database")
# Use higher port numbers that don't conflict with the Vault server
LISTENER_PORTS=(8100 8200) # Corresponding local ports for Vault Agent API endpoints

echo -e "${BLUE}=== Vault Agent Per-App Isolation Demo ===${NC}"
echo "This script demonstrates using separate Vault Agents with systemd integration for applications."

# Check if vault is installed
if ! command -v vault &> /dev/null; then
    echo -e "${RED}Error: Vault CLI is not installed.${NC}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed.${NC}"
    exit 1
fi

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: This script must be run as root (required for systemd operations).${NC}"
  echo "Please run with sudo or as root user."
  exit 1
fi

echo -e "\n${GREEN}Creating dedicated users for Vault Agents and applications...${NC}"
# Create vaultagent user for running Vault Agents
id -u $VAULTAGENT_USER &>/dev/null || useradd -r -s /bin/false $VAULTAGENT_USER

# Create appuser for running applications (optional, in practice you'd use existing app users)
id -u $APP_USER &>/dev/null || useradd -r -s /bin/bash $APP_USER

# Create scripts directory for the app user
mkdir -p $APP_SCRIPTS_DIR
chown $APP_USER:$APP_USER $APP_SCRIPTS_DIR
chmod 755 $APP_SCRIPTS_DIR

echo -e "\n${GREEN}Starting Vault in dev mode...${NC}"
echo "In a separate terminal window, please run:"
echo -e "${BLUE}vault server -dev -dev-root-token-id=\"root\"${NC}"
echo "Then press Enter to continue..."
read

# Set environment variables
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

# Verify Vault is running
if ! vault status &> /dev/null; then
    echo -e "${RED}Error: Vault server is not running.${NC}"
    exit 1
fi

echo -e "\n${GREEN}Vault server is running.${NC}"

# Create the data directory
echo -e "\n${GREEN}Creating Vault Agent data directory...${NC}"
mkdir -p $VAULT_DATA_DIR
chmod 755 $VAULT_DATA_DIR  # Changed to 755 to allow all users to access the directory
chown root:root $VAULT_DATA_DIR

echo -e "\n${GREEN}Creating application directories...${NC}"
# Create directories for each app
for app_name in "${APP_NAMES[@]}"; do
    mkdir -p $(printf $APP_DATA_DIR_FORMAT $app_name)
    # Allow appuser to traverse into these directories
    chmod 750 $(printf $APP_DATA_DIR_FORMAT $app_name)
    # Set group to appuser so they can access token files
    chown $VAULTAGENT_USER:$APP_USER $(printf $APP_DATA_DIR_FORMAT $app_name)
done

echo -e "\n${GREEN}Creating policies...${NC}"
# Create policies for each app
for app_name in "${APP_NAMES[@]}"; do
    cat > $VAULT_DATA_DIR/${app_name}-policy.hcl << EOF
path "secret/data/${app_name}/*" {
  capabilities = ["read", "list"]
}
EOF
    vault policy write ${app_name}-policy $VAULT_DATA_DIR/${app_name}-policy.hcl
done

# Create policy for restart role
cat > $VAULT_DATA_DIR/restart-policy.hcl << EOF
# Allow creating wrapped secret IDs for any app role
path "auth/approle/role/+/secret*" {
  capabilities = ["create", "read", "update"]
  min_wrapping_ttl = "100s"
  max_wrapping_ttl = "300s"
}

# Allow reading role IDs for any app role
path "auth/approle/role/+/role-id" {
  capabilities = ["read"]
}
EOF

# Apply the restart policy
vault policy write restart-policy $VAULT_DATA_DIR/restart-policy.hcl

echo -e "\n${GREEN}Enabling secrets engine...${NC}"
# Enable KV secrets engine
vault secrets enable -version=2 -path=secret kv 2>/dev/null || echo "Secret engine already enabled"

echo -e "\n${GREEN}Creating sample secrets...${NC}"
# Create sample secrets for each app
for app_name in "${APP_NAMES[@]}"; do
    vault kv put secret/${app_name}/config api-key="${app_name}-secret-key" db-password="${app_name}-db-password"
done

echo -e "\n${GREEN}Setting up AppRole authentication...${NC}"
# Enable AppRole auth method
vault auth enable approle 2>/dev/null || echo "AppRole already enabled"

# Create AppRole for each app
for app_name in "${APP_NAMES[@]}"; do
    vault write auth/approle/role/${app_name}-role \
        secret_id_ttl=2h \
        token_num_uses=100 \
        token_ttl=5h \
        token_max_ttl=24h \
        secret_id_num_uses=150 \
        token_policies="${app_name}-policy"
done

# Create restart AppRole with infinite TTL for the secret-id
vault write -force auth/approle/role/restart-role \
    secret_id_num_uses=0 \
    token_policies="restart-policy"

echo -e "\n${GREEN}Creating restart role credentials...${NC}"
# Only get the restart role credentials
vault read -format=json auth/approle/role/restart-role/role-id | jq -r '.data.role_id' > $VAULT_DATA_DIR/restart-role-id
vault write -f -format=json auth/approle/role/restart-role/secret-id | jq -r '.data.secret_id' > $VAULT_DATA_DIR/restart-secret-id

# Set proper permissions for restart credentials
chmod 600 $VAULT_DATA_DIR/restart-role-id $VAULT_DATA_DIR/restart-secret-id
chown $VAULTAGENT_USER:$VAULTAGENT_USER $VAULT_DATA_DIR/restart-role-id $VAULT_DATA_DIR/restart-secret-id

echo -e "\n${GREEN}Creating the vault agent startup scripts...${NC}"
# Create a startup script for each app
for i in "${!APP_NAMES[@]}"; do
    app_name=${APP_NAMES[$i]}
    
    cat > $VAULT_DATA_DIR/${app_name}-agent-start.sh << EOF
#!/bin/bash
# Startup script for Vault Agent for ${app_name}

export VAULT_ADDR='http://127.0.0.1:8200'
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
vault read -field=role_id auth/approle/role/${app_name}-role/role-id > \$APP_DIR/role-id
chmod 600 \$APP_DIR/role-id

# Write a wrapped secret-id to the expected location
vault write -field=wrapping_token -wrap-ttl=200s -f auth/approle/role/${app_name}-role/secret-id > \$APP_DIR/wrapped-secret-id
chmod 600 \$APP_DIR/wrapped-secret-id

# Start the agent
exec vault agent -config=$VAULT_DATA_DIR/${app_name}-agent.hcl
EOF

    chmod 700 $VAULT_DATA_DIR/${app_name}-agent-start.sh
    chown $VAULTAGENT_USER:$VAULTAGENT_USER $VAULT_DATA_DIR/${app_name}-agent-start.sh
done

echo -e "\n${GREEN}Creating Vault Agent configurations...${NC}"
# Create Vault Agent configuration for each app
for i in "${!APP_NAMES[@]}"; do
    app_name=${APP_NAMES[$i]}
    port=${LISTENER_PORTS[$i]}
    
    cat > $VAULT_DATA_DIR/${app_name}-agent.hcl << EOF
exit_after_auth = false
pid_file = "$VAULT_DATA_DIR/${app_name}/vault-agent.pid"

vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "$(printf $ROLE_ID_FILE_FORMAT $app_name)"
      secret_id_file_path = "$(printf $WRAPPED_SECRET_ID_FILE_FORMAT $app_name)"
      remove_secret_id_file_after_reading = true
      secret_id_response_wrapping_path = "auth/approle/role/${app_name}-role/secret-id"
    }
  }

  sink "file" {
    config = {
      path = "$(printf $TOKEN_SINK_FORMAT $app_name)"
      mode = 0440
      # Allow the app users to read the token
      user = "$VAULTAGENT_USER"
      group = "$APP_USER"
    }
  }
}

listener "tcp" {
  address = "127.0.0.1:${port}"
  tls_disable = true
}

cache {
  use_auto_auth_token = true
}
EOF

    chmod 640 $VAULT_DATA_DIR/${app_name}-agent.hcl
    chown $VAULTAGENT_USER:$VAULTAGENT_USER $VAULT_DATA_DIR/${app_name}-agent.hcl
done

echo -e "\n${GREEN}Creating systemd service files...${NC}"
# Create systemd service for each app
for app_name in "${APP_NAMES[@]}"; do
    cat > /etc/systemd/system/vault-agent-${app_name}.service << EOF
[Unit]
Description=Vault Agent for ${app_name^}
After=network.target

[Service]
Type=simple
ExecStart=$VAULT_DATA_DIR/${app_name}-agent-start.sh
Restart=on-failure
RestartSec=10
User=$VAULTAGENT_USER
Group=$VAULTAGENT_USER

[Install]
WantedBy=multi-user.target
EOF
done

echo -e "\n${GREEN}Creating test applications...${NC}"
# Create test application scripts
for i in "${!APP_NAMES[@]}"; do
    app_name=${APP_NAMES[$i]}
    port=${LISTENER_PORTS[$i]}
    other_apps=""
    script_path="$APP_SCRIPTS_DIR/${app_name}-script.py"
    
    # Properly create the array of other apps for testing
    for other_app in "${APP_NAMES[@]}"; do
        if [ "$other_app" != "$app_name" ]; then
            other_apps+="\"$other_app\", "
        fi
    done
    # Remove trailing comma and space
    other_apps=${other_apps%, }
    
    cat > $script_path << EOF
#!/usr/bin/env python3
import os
import requests
import json
import time

TOKEN_PATH = '$(printf $TOKEN_SINK_FORMAT $app_name)'
VAULT_ADDR = 'http://127.0.0.1:8200'
AGENT_ADDR = 'http://127.0.0.1:${port}'

# Wait for token to be available
attempts = 0
while not os.path.exists(TOKEN_PATH) and attempts < 30:
    print("Waiting for Vault token...")
    time.sleep(1)
    attempts += 1

if not os.path.exists(TOKEN_PATH):
    print("Error: Token file not found after waiting")
    exit(1)

# Read the token
with open(TOKEN_PATH, 'r') as f:
    vault_token = f.read().strip()

# Set up headers
headers = {
    'X-Vault-Token': vault_token
}

# Get secrets from Vault server directly
response = requests.get(
    f'{VAULT_ADDR}/v1/secret/data/${app_name}/config', 
    headers=headers
)

# Alternatively, using the Vault Agent API
# response = requests.get(
#     f'{AGENT_ADDR}/v1/secret/data/${app_name}/config',
#     headers=headers
# )

print(f"${app_name} retrieving secrets:")
if response.status_code == 200:
    secrets = response.json()['data']['data']
    print(f"  API Key: {secrets['api-key']}")
    print(f"  DB Password: {secrets['db-password']}")
else:
    print(f"  Error: {response.status_code}")
    print(f"  Response: {response.text}")

# Try to access secrets from other apps to test isolation
other_apps = [${other_apps}]
for other_app in other_apps:
    print(f"${app_name} attempting to access {other_app} secrets (should fail):")
    response = requests.get(
        f'{VAULT_ADDR}/v1/secret/data/{other_app}/config',
        headers=headers
    )
    if response.status_code != 200:
        print(f"  Access correctly denied: {response.status_code}")
    else:
        print(f"  ERROR: Access incorrectly granted to {other_app} secrets!")
EOF

    # Set proper file permissions - owned fully by app user
    chmod 755 $script_path
    chown $APP_USER:$APP_USER $script_path
    
    # Verify the permissions are set correctly
    echo "Created script with permissions:"
    ls -la $script_path
done

echo -e "\n${GREEN}Reloading systemd and enabling services...${NC}"
systemctl daemon-reload

for app_name in "${APP_NAMES[@]}"; do
    systemctl enable vault-agent-${app_name}.service
done

echo -e "\n${GREEN}Starting Vault Agent services...${NC}"
for app_name in "${APP_NAMES[@]}"; do
    systemctl start vault-agent-${app_name}.service
done

# Wait for tokens to be created
echo "Waiting for tokens to be created..."
sleep 10

# Check if tokens were created
tokens_created=true
for app_name in "${APP_NAMES[@]}"; do
    token_path=$(printf $TOKEN_SINK_FORMAT $app_name)
    if [ ! -f "$token_path" ]; then
        echo -e "${RED}Error: Token for ${app_name} was not created.${NC}"
        echo "Check the service logs with: journalctl -u vault-agent-${app_name}.service"
        tokens_created=false
    else
        # Verify permissions on token files
        ls -l $token_path
        
        # Fix token file permissions if needed - don't change ownership if already set
        if [ "$(stat -c '%G' $token_path)" != "$APP_USER" ]; then
            echo "Fixing permissions on token file for $app_name"
            chmod 440 $token_path
            chown $VAULTAGENT_USER:$APP_USER $token_path
            ls -l $token_path
        fi
    fi
done

if [ "$tokens_created" = false ]; then
    echo -e "${RED}One or more tokens were not created. Check the logs for details.${NC}"
    exit 1
else
    echo -e "${GREEN}All tokens created successfully!${NC}"
fi

echo -e "\n${GREEN}Testing application access with tokens...${NC}"
for app_name in "${APP_NAMES[@]}"; do
    script_path="$APP_SCRIPTS_DIR/${app_name}-script.py"
    echo -e "\n${BLUE}Running ${app_name} script as $APP_USER:${NC}"
    
    # Verify script exists and has correct permissions before running
    if [ -f "$script_path" ] && [ -x "$script_path" ]; then
        sudo -u $APP_USER python3 $script_path
    else
        echo -e "${RED}Error: Script $script_path is not accessible or executable by $APP_USER${NC}"
        ls -la $script_path
    fi
done

echo -e "\n${GREEN}Demonstration completed!${NC}"
echo ""
echo "The system is now set up with:"
echo "1. A dedicated '$VAULTAGENT_USER' user for running Vault Agents"
echo "2. A dedicated '$APP_USER' user for applications accessing tokens"
echo "3. Proper file permissions ensuring separation of concerns"
echo "4. A restart AppRole with tightly scoped permissions"
echo "5. Systemd services running as non-root user"
echo "6. Complete isolation between applications with cached API endpoints"
echo ""
echo "The following applications were configured:"
for i in "${!APP_NAMES[@]}"; do
    port=${LISTENER_PORTS[$i]}
    echo "  - ${APP_NAMES[$i]}: API endpoint at http://127.0.0.1:${port}"
done
echo ""
echo "To clean up when you're done (not required now):"
echo "  sudo systemctl stop $(printf "vault-agent-%s " "${APP_NAMES[@]}")"
echo "  sudo systemctl disable $(printf "vault-agent-%s " "${APP_NAMES[@]}")"
echo "  sudo rm -f $(printf "/etc/systemd/system/vault-agent-%s.service " "${APP_NAMES[@]}")"
echo "  sudo rm -rf $VAULT_DATA_DIR"
echo "  sudo systemctl daemon-reload"
echo "  sudo userdel $VAULTAGENT_USER"
echo "  sudo userdel $APP_USER"
echo ""
echo -e "${BLUE}=== Demo Complete ===${NC}"
echo "You can continue to experiment with the setup or stop the Vault dev server when you're done." 