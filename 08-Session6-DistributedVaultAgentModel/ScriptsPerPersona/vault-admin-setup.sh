#!/bin/bash
# Vault Admin Setup Script
# This script is used by the Vault Administrator (IT Security) to set up:
# 1. Policies for each application
# 2. The restart AppRole with its policy (optional, only needs to be done once)
# 3. Application-specific AppRoles
# 4. Sample secrets for testing

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Temporary directory for policy files
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo -e "\n${BLUE}=== Vault Admin Setup (IT Security) ===${NC}"
echo "This script will set up the necessary Vault configuration for applications."

# Export Vault Address and Token if not already set
if [ -z "$VAULT_ADDR" ]; then
    read -p "Enter Vault server address [$VAULT_ADDR]: " input
    VAULT_ADDR=${input:-$VAULT_ADDR}
    export VAULT_ADDR
fi

if [ -z "$VAULT_TOKEN" ]; then
    echo "Please authenticate to Vault:"
    vault login
fi

# Verify Vault is running and we have access
if ! vault status &> /dev/null; then
    echo -e "${RED}Error: Vault server is not running or not accessible.${NC}"
    exit 1
fi

echo -e "\n${GREEN}Vault server is accessible.${NC}"

# Function to setup restart AppRole
setup_restart_approle() {
    echo -e "\n${GREEN}Setting up restart AppRole...${NC}"
    
    # Check if restart policy already exists
    if vault policy read restart &>/dev/null; then
        echo "Restart policy already exists, skipping creation."
    else
        # Create policy for restart role
        echo "Creating restart policy..."
        cat > "$TMP_DIR/restart.hcl" << EOF
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
        vault policy write restart "$TMP_DIR/restart.hcl"
        echo "Created restart"
    fi

    # Check if restart AppRole already exists
    if vault read auth/approle/role/restart &>/dev/null; then
        echo "Restart AppRole already exists, skipping creation."
    else
        # Create restart AppRole with infinite TTL for the secret-id
        echo "Creating restart AppRole..."
        vault write -force auth/approle/role/restart \
            secret_id_num_uses=0 \
            token_policies="restart"
        echo "Created restart AppRole"
    fi

    # Generate the restart role credentials
    restart_role_id=$(vault read -format=json auth/approle/role/restart/role-id | jq -r '.data.role_id')
    restart_secret_id=$(vault write -f -format=json auth/approle/role/restart/secret-id | jq -r '.data.secret_id')

    # Output the restart role credentials (for SysAdmin)
    echo -e "\n${BLUE}==== RESTART APPROLE CREDENTIALS ====${NC}"
    echo "Please securely share these credentials with your System Administrators."
    echo "These credentials will be used by SysAdmins to configure Vault Agents."
    echo -e "${GREEN}Restart Role ID:${NC} $restart_role_id"
    echo -e "${GREEN}Restart Secret ID:${NC} $restart_secret_id"

    # Create a credentials file that can be securely transferred to SysAdmins
    credentials_file="$TMP_DIR/restart-approle-credentials.json"
    cat > "$credentials_file" << EOF
{
  "role_id": "$restart_role_id",
  "secret_id": "$restart_secret_id"
}
EOF

    echo -e "\n${BLUE}Credentials saved to:${NC} $credentials_file"
    echo "Transfer this file securely to your System Administrators."
    echo "Consider using a secure file transfer method"
}

# Function to setup application AppRoles and policies
setup_application_approles() {
    # List of applications to set up - MODIFY THIS LIST for your environment
    echo -e "\n${GREEN}Enter the application names (space-separated):${NC}"
    read -p "Applications: " APP_NAMES_INPUT
    IFS=' ' read -r -a APP_NAMES <<< "$APP_NAMES_INPUT"

    if [ ${#APP_NAMES[@]} -eq 0 ]; then
        echo "No applications specified. Using default examples: webapp database"
        APP_NAMES=("webapp" "database")
    fi

    echo -e "\n${BLUE}Setting up policies and AppRoles for: ${APP_NAMES[*]}${NC}"

    echo -e "\n${GREEN}Creating policies...${NC}"
    # Create policies for each app
    for app_name in "${APP_NAMES[@]}"; do
        echo "Creating policy for $app_name..."
        
        if vault policy read "${app_name}" &>/dev/null; then
            echo "Policy ${app_name} already exists, updating..."
        fi
        
        cat > "$TMP_DIR/${app_name}.hcl" << EOF
path "secret/data/${app_name}/*" {
  capabilities = ["read", "list"]
}
EOF
        vault policy write "${app_name}" "$TMP_DIR/${app_name}.hcl"
        echo "Created/Updated ${app_name}"
    done

    echo -e "\n${GREEN}Enabling secrets engine...${NC}"
    # Enable KV secrets engine if not already enabled
    vault secrets enable -version=2 -path=secret kv 2>/dev/null || echo "Secret engine already enabled"

    echo -e "\n${GREEN}Creating application secrets...${NC}"
    # Ask if user wants to use default sample secrets or enter custom ones
    echo -e "${BLUE}Would you like to:${NC}"
    echo "1. Use default sample secrets (api-key and db-password)"
    echo "2. Enter custom key-value pairs for each application"
    read -p "Choice [1]: " secret_choice
    secret_choice=${secret_choice:-1}
    
    # Create secrets for each app
    for app_name in "${APP_NAMES[@]}"; do
        if [ "$secret_choice" == "1" ]; then
            # Use default sample secrets
            vault kv put "secret/${app_name}/config" \
                api-key="${app_name}-secret-key" \
                db-password="${app_name}-db-password"
            echo "Created/Updated default sample secrets for ${app_name}"
        else
            # Custom secrets input
            echo -e "\n${GREEN}Enter key-value pairs for ${app_name}:${NC}"
            echo "For each secret, enter the key followed by the value."
            echo "Enter a blank key when finished."
            
            # Build the command dynamically
            cmd="vault kv put secret/${app_name}/config"
            secret_count=0
            
            while true; do
                read -p "Key (or press Enter to finish): " secret_key
                if [ -z "$secret_key" ]; then
                    # Empty key means we're done
                    break
                fi
                read -p "Value for $secret_key: " secret_value
                if [ -z "$secret_value" ]; then
                    echo -e "${RED}Warning: Empty value provided for key '$secret_key'. Using empty string.${NC}"
                fi
                
                # Add this key-value pair to the command
                cmd="$cmd $secret_key=\"$secret_value\""
                ((secret_count++))
            done
            
            # Check if any secrets were provided
            if [ $secret_count -eq 0 ]; then
                echo -e "${RED}No secrets provided. Using default values instead.${NC}"
                vault kv put "secret/${app_name}/config" \
                    api-key="${app_name}-secret-key" \
                    db-password="${app_name}-db-password"
            else
                # Execute the command with all key-value pairs
                eval $cmd
                echo "Created/Updated ${secret_count} custom secrets for ${app_name}"
            fi
        fi
    done

    echo -e "\n${GREEN}Setting up AppRole authentication...${NC}"
    # Enable AppRole auth method if not already enabled
    vault auth enable approle 2>/dev/null || echo "AppRole already enabled"

    # Create AppRole for each app
    for app_name in "${APP_NAMES[@]}"; do
        echo "Creating/Updating AppRole for ${app_name}..."
        vault write "auth/approle/role/${app_name}" \
            secret_id_ttl=2h \
            token_num_uses=100 \
            token_ttl=5h \
            token_max_ttl=24h \
            secret_id_num_uses=150 \
            token_policies="${app_name}"
        echo "Created/Updated ${app_name} AppRole"
    done

    # Generate a list of application information for DevOps
    echo -e "\n${BLUE}==== APPLICATION INFORMATION FOR DEVOPS ====${NC}"
    echo "The following information should be provided to the DevOps team:"

    for app_name in "${APP_NAMES[@]}"; do
        echo -e "${GREEN}${app_name}:${NC}"
        echo "- AppRole Name: ${app_name}"
        echo "- Token Sink Path: /home/springApps/.vault-tokens/${app_name}-token"
        echo ""
    done
}

# Main execution flow - ask the user what they want to do
echo -e "\n${BLUE}What would you like to set up?${NC}"
echo "1. Set up restart AppRole (only needed once per environment)"
echo "2. Set up application AppRoles and policies"
echo "3. Both (complete setup)"
read -p "Choice [3]: " setup_choice
setup_choice=${setup_choice:-3}

case $setup_choice in
    1)
        setup_restart_approle
        ;;
    2)
        setup_application_approles
        ;;
    3)
        setup_restart_approle
        setup_application_approles
        ;;
    *)
        echo -e "${RED}Invalid choice. Exiting.${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}Vault Admin setup complete!${NC}"
echo "Summary:"
if [ "$setup_choice" == "1" ] || [ "$setup_choice" == "3" ]; then
    echo "✓ Created/verified restart AppRole with appropriate permissions"
    echo "✓ Generated restart AppRole credentials for SysAdmins"
fi
if [ "$setup_choice" == "2" ] || [ "$setup_choice" == "3" ]; then
    echo "✓ Created/updated policies for each application"
    echo "✓ Created/updated application-specific AppRoles"
    echo "✓ Generated application information for DevOps"
fi
echo ""
echo "Next steps:"
if [ "$setup_choice" == "1" ] || [ "$setup_choice" == "3" ]; then
    echo "1. Securely transfer restart AppRole credentials to SysAdmins"
fi
if [ "$setup_choice" == "2" ] || [ "$setup_choice" == "3" ]; then
    echo "2. Share application information with DevOps"
fi
echo "" 