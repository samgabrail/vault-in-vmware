#!/bin/bash
##############################################################################
# Vault Admin Setup Script
# 
# PURPOSE:
# This script is used by the Vault Administrator (IT Security) to set up all
# necessary components for a secure application authentication workflow.
# 
# COMPONENTS CREATED:
# 1. Policies for each application to limit access to specific secret paths
# 2. The restart AppRole with special permissions (only needed once per environment)
# 3. Application-specific AppRoles configured with appropriate TTLs and token limits
# 4. Sample secrets for testing and development
#
# WORKFLOW OVERVIEW:
# - The script requires Vault CLI and jq to be installed
# - It authenticates to Vault as an admin user
# - It offers different setup options (restart AppRole only, application AppRoles only, or both)
# - Configuration is interactive with sensible defaults
##############################################################################

# ANSI color codes for better readability in terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Verify dependencies are installed
# ----------------------------------------------------------------------------
# Check if vault CLI is installed - critical for all operations
if ! command -v vault &> /dev/null; then
    echo -e "${RED}Error: Vault CLI is not installed.${NC}"
    echo "Please install the Vault CLI before running this script."
    echo "Visit https://developer.hashicorp.com/vault/downloads for installation instructions."
    exit 1
fi

# Check if jq is installed - needed for JSON parsing
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed.${NC}"
    echo "The jq utility is required for JSON parsing operations."
    echo "Install using: apt-get install jq (Debian/Ubuntu) or yum install jq (CentOS/RHEL)"
    exit 1
fi

# Create temporary directory to store policy files
# Clean up this directory when script exits using trap
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo -e "\n${BLUE}=== Vault Admin Setup (IT Security) ===${NC}"
echo "This script will set up the necessary Vault configuration for applications."

# ----------------------------------------------------------------------------
# Configure Vault connection settings
# ----------------------------------------------------------------------------
# Export Vault Address if not already set in environment
if [ -z "$VAULT_ADDR" ]; then
    read -p "Enter Vault server address [$VAULT_ADDR]: " input
    VAULT_ADDR=${input:-$VAULT_ADDR}
    export VAULT_ADDR
fi

# Authentication to Vault
# ----------------------------------------------------------------------------
# Authenticate to Vault if not already authenticated (token not in env)
if [ -z "$VAULT_TOKEN" ]; then
    echo -e "\n${BLUE}Select authentication method:${NC}"
    echo "1. Token"
    echo "2. LDAP"
    read -p "Choice [1]: " auth_method
    auth_method=${auth_method:-1}
    
    case $auth_method in
        1)
            # Token authentication - simplest method
            echo "Please authenticate to Vault with your token:"
            vault login
            ;;
        2)
            # LDAP authentication - requires LDAP auth method to be enabled
            read -p "Enter LDAP username: " ldap_username
            echo "You will be prompted for your LDAP password next (input will not be displayed)"
            vault login -method=ldap username="$ldap_username"
            ;;
        *)
            # Default to token authentication for invalid choices
            echo -e "${RED}Invalid choice. Defaulting to token authentication.${NC}"
            vault login
            ;;
    esac
fi

# Verify Vault is accessible with current credentials
if ! vault status &> /dev/null; then
    echo -e "${RED}Error: Vault server is not running or not accessible.${NC}"
    echo "Please check:"
    echo "1. Vault server is running"
    echo "2. VAULT_ADDR is correct"
    echo "3. Network connectivity to Vault"
    echo "4. Your authentication token has sufficient permissions"
    exit 1
fi

echo -e "\n${GREEN}Vault server is accessible.${NC}"

# ----------------------------------------------------------------------------
# Function to setup restart AppRole
# The restart AppRole is a special role used by the System Administrators
# to bootstrap the application-specific AppRoles. It has limited permissions
# to read role IDs and create wrapped secret IDs.
# ----------------------------------------------------------------------------
setup_restart_approle() {
    echo -e "\n${GREEN}Setting up restart AppRole...${NC}"
    
    # Check if restart policy already exists to avoid duplication
    if vault policy read restart &>/dev/null; then
        echo "Restart policy already exists, skipping creation."
    else
        # Create policy for restart role - this defines what the restart role can do
        echo "Creating restart policy..."
        cat > "$TMP_DIR/restart.hcl" << EOF
# Allow creating wrapped secret IDs for any app role
# This allows the restart role to generate wrapped secret IDs that can
# only be unwrapped by the target application's Vault Agent
path "auth/approle/role/+/secret*" {
  capabilities = ["create", "read", "update"]
  min_wrapping_ttl = "100s"
  max_wrapping_ttl = "300s"
}

# Allow reading role IDs for any app role
# Role IDs are not considered sensitive since they require the secret ID
# to authenticate, similar to a username requiring a password
path "auth/approle/role/+/role-id" {
  capabilities = ["read"]
}
EOF

        # Apply the restart policy to Vault
        vault policy write restart "$TMP_DIR/restart.hcl"
        echo "Created restart policy"
    fi

    # Enable AppRole auth method if not already enabled
    # AppRole is the authentication method used for machine-to-machine auth
    echo -e "\n${GREEN}Ensuring AppRole authentication is enabled...${NC}"
    if vault auth list | grep -q "approle/"; then
        echo "AppRole auth method is already enabled"
    else
        echo "Enabling AppRole auth method..."
        vault auth enable approle
        if [ $? -eq 0 ]; then
            echo "Successfully enabled AppRole auth method"
        else
            echo -e "${RED}Error: Failed to enable AppRole auth method. Aborting.${NC}"
            echo "Check that your token has sufficient permissions to enable auth methods."
            exit 1
        fi
    fi

    # Check if restart AppRole already exists to avoid duplication
    if vault read auth/approle/role/restart &>/dev/null; then
        echo "Restart AppRole already exists, skipping creation."
    else
        # Create restart AppRole with infinite TTL for the secret-id
        # Setting secret_id_num_uses=0 means the secret ID never expires after N uses
        echo "Creating restart AppRole..."
        vault write -force auth/approle/role/restart \
            secret_id_num_uses=0 \
            token_policies="restart"
        echo "Created restart AppRole"
    fi

    # Generate the restart role credentials (role ID and secret ID)
    # These credentials will be given to the System Administrator
    echo "Generating restart role credentials..."
    restart_role_id=$(vault read -format=json auth/approle/role/restart/role-id | jq -r '.data.role_id')
    
    # Error handling for role ID retrieval
    if [ -z "$restart_role_id" ] || [ "$restart_role_id" == "null" ]; then
        echo -e "${RED}Error: Failed to retrieve role ID for restart AppRole.${NC}"
        echo "Please check that the AppRole was created successfully."
        exit 1
    fi
    
    # Generate a secret ID for the restart role
    restart_secret_id=$(vault write -f -format=json auth/approle/role/restart/secret-id | jq -r '.data.secret_id')
    
    # Error handling for secret ID generation
    if [ -z "$restart_secret_id" ] || [ "$restart_secret_id" == "null" ]; then
        echo -e "${RED}Error: Failed to generate secret ID for restart AppRole.${NC}"
        exit 1
    fi

    # Output the restart role credentials for System Administrators
    echo -e "\n${BLUE}==== RESTART APPROLE CREDENTIALS ====${NC}"
    echo "Please securely share these credentials with your System Administrators."
    echo "These credentials will be used by SysAdmins to configure Vault Agents."
    echo -e "${GREEN}Restart Role ID:${NC} $restart_role_id"
    echo -e "${GREEN}Restart Secret ID:${NC} $restart_secret_id"

    # Provide options for saving credentials to a file
    echo -e "\n${BLUE}Where would you like to save the credentials file?${NC}"
    echo "1. Current directory (./restart-approle-credentials.json)"
    echo "2. Custom path"
    echo "3. Don't save to file (display only)"
    read -p "Option [1]: " save_option
    save_option=${save_option:-1}
    
    # Format credentials as JSON for easier consumption by other tools
    credentials_json="{
  \"role_id\": \"$restart_role_id\",
  \"secret_id\": \"$restart_secret_id\"
}"

    # Handle different save options
    case $save_option in
        1)
            # Save to current directory
            credentials_file="./restart-approle-credentials.json"
            echo "$credentials_json" > "$credentials_file"
            echo -e "\n${BLUE}Credentials saved to:${NC} $credentials_file"
            ;;
        2)
            # Save to custom path
            read -p "Enter the path where you want to save the credentials file: " custom_path
            # Ensure the directory exists
            credentials_dir=$(dirname "$custom_path")
            mkdir -p "$credentials_dir" 2>/dev/null
            echo "$credentials_json" > "$custom_path"
            echo -e "\n${BLUE}Credentials saved to:${NC} $custom_path"
            ;;
        3)
            # Don't save to file
            echo -e "\n${BLUE}Credentials not saved to file. Please copy them from above.${NC}"
            ;;
        *)
            # Invalid option
            echo -e "${RED}Invalid option. Credentials not saved to file.${NC}"
            ;;
    esac
    
    echo "Transfer these credentials securely to your System Administrators."
    echo "Consider using a secure file transfer method or a secret management tool."
}

# ----------------------------------------------------------------------------
# Function to setup application AppRoles and policies
# These AppRoles will be used by application instances to authenticate to Vault
# and retrieve their secrets. Each application gets its own AppRole with
# appropriate policies limiting access to only its secrets.
# ----------------------------------------------------------------------------
setup_application_approles() {
    # Get list of applications to set up 
    echo -e "\n${GREEN}Enter the application names (space-separated):${NC}"
    read -p "Applications: " APP_NAMES_INPUT
    IFS=' ' read -r -a APP_NAMES <<< "$APP_NAMES_INPUT"

    # Use default applications if none specified
    if [ ${#APP_NAMES[@]} -eq 0 ]; then
        echo "No applications specified. Using default examples: webapp database"
        APP_NAMES=("webapp" "database")
    fi

    echo -e "\n${BLUE}Setting up policies and AppRoles for: ${APP_NAMES[*]}${NC}"

    # Create policies for each application
    # ----------------------------------------------------------------------------
    echo -e "\n${GREEN}Creating policies...${NC}"
    # Iterate through each application to create or update its policy
    for app_name in "${APP_NAMES[@]}"; do
        echo "Creating policy for $app_name..."
        
        # Check if policy already exists
        if vault policy read "${app_name}" &>/dev/null; then
            echo "Policy ${app_name} already exists, updating..."
        fi
        
        # Create policy file - limits access to only this application's secrets
        # This implements the principle of least privilege
        cat > "$TMP_DIR/${app_name}.hcl" << EOF
path "secret/data/${app_name}/*" {
  capabilities = ["read", "list"]
}
EOF
        # Apply the policy to Vault
        vault policy write "${app_name}" "$TMP_DIR/${app_name}.hcl"
        echo "Created/Updated ${app_name} policy"
    done

    # Setup secrets engine for storing application secrets
    # ----------------------------------------------------------------------------
    echo -e "\n${GREEN}Enabling secrets engine...${NC}"
    # Enable KV version 2 secrets engine if not already enabled
    # KV v2 provides versioning of secrets
    vault secrets enable -version=2 -path=secret kv 2>/dev/null || echo "Secret engine already enabled"

    # Create sample secrets for each application
    # ----------------------------------------------------------------------------
    echo -e "\n${GREEN}Creating application secrets...${NC}"
    # Ask if user wants default or custom secrets
    echo -e "${BLUE}Would you like to:${NC}"
    echo "1. Use default sample secrets (api-key and db-password)"
    echo "2. Enter custom key-value pairs for each application"
    read -p "Choice [1]: " secret_choice
    secret_choice=${secret_choice:-1}
    
    # Process each application
    for app_name in "${APP_NAMES[@]}"; do
        if [ "$secret_choice" == "1" ]; then
            # Use default sample secrets - simplest option
            vault kv put "secret/${app_name}/config" \
                api-key="${app_name}-secret-key" \
                db-password="${app_name}-db-password"
            echo "Created/Updated default sample secrets for ${app_name}"
        else
            # Custom secrets input - more flexible but requires more input
            echo -e "\n${GREEN}Enter key-value pairs for ${app_name}:${NC}"
            echo "For each secret, enter the key followed by the value."
            echo "Enter a blank key when finished."
            
            # Build the command dynamically based on user input
            cmd="vault kv put secret/${app_name}/config"
            secret_count=0
            
            # Loop to collect key-value pairs
            while true; do
                read -p "Key (or press Enter to finish): " secret_key
                if [ -z "$secret_key" ]; then
                    # Empty key means we're done collecting secrets
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
            
            # Handle case where no secrets were provided
            if [ $secret_count -eq 0 ]; then
                echo -e "${RED}No secrets provided. Using default values instead.${NC}"
                vault kv put "secret/${app_name}/config" \
                    api-key="${app_name}-secret-key" \
                    db-password="${app_name}-db-password"
            else
                # Execute the dynamically built command to store secrets
                eval $cmd
                echo "Created/Updated ${secret_count} custom secrets for ${app_name}"
            fi
        fi
    done

    # Create AppRoles for applications
    # ----------------------------------------------------------------------------
    echo -e "\n${GREEN}Setting up AppRole authentication...${NC}"
    # Verify AppRole auth method is enabled
    if vault auth list | grep -q "approle/"; then
        echo "AppRole auth method is already enabled"
    else
        echo "Enabling AppRole auth method..."
        vault auth enable approle
        if [ $? -eq 0 ]; then
            echo "Successfully enabled AppRole auth method"
        else
            echo -e "${RED}Error: Failed to enable AppRole auth method. Aborting.${NC}"
            exit 1
        fi
    fi

    # Create an AppRole for each application with appropriate settings
    for app_name in "${APP_NAMES[@]}"; do
        echo "Creating/Updating AppRole for ${app_name}..."
        # Configure the AppRole with security settings:
        # - secret_id_ttl: How long the secret ID is valid
        # - token_num_uses: How many times the token can be used
        # - token_ttl: How long the token is valid
        # - token_max_ttl: Maximum validity period for the token
        # - secret_id_num_uses: How many times the secret ID can be used
        # - token_policies: What policies to attach to tokens
        vault write "auth/approle/role/${app_name}" \
            secret_id_ttl=24h \
            token_num_uses=100 \
            token_ttl=5h \
            token_max_ttl=24h \
            secret_id_num_uses=150 \
            token_bound_cidrs="127.0.0.1/32, 127.0.0.2/32" \
            secret_id_bound_cidrs="127.0.0.1/32, 127.0.0.2/32" \
            token_policies="${app_name}"
        echo "Created/Updated ${app_name} AppRole"
    done

    # Generate application information for DevOps team
    # ----------------------------------------------------------------------------
    echo -e "\n${BLUE}==== APPLICATION INFORMATION FOR DEVOPS ====${NC}"
    echo "The following information should be provided to the DevOps team:"

    for app_name in "${APP_NAMES[@]}"; do
        echo -e "${GREEN}${app_name}:${NC}"
        echo "- AppRole Name: ${app_name}"
        echo "- Token Sink Path: /home/springapps/.vault-tokens/${app_name}-token"
        echo ""
    done
}

# ----------------------------------------------------------------------------
# Main program execution flow
# ----------------------------------------------------------------------------
echo -e "\n${BLUE}What would you like to set up?${NC}"
echo "1. Set up restart AppRole (only needed once per environment)"
echo "2. Set up application AppRoles and policies"
echo "3. Both (complete setup)"
read -p "Choice [3]: " setup_choice
setup_choice=${setup_choice:-3}

# Execute the requested setup operations
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

# Provide a summary of what was completed
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