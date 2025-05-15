#!/bin/bash
##############################################################################
# Vault Raft Snapshot Policy and AppRole Setup Script
#
# PURPOSE:
# This script creates a dedicated Vault policy for Raft snapshots and sets up
# an AppRole authentication method with an infinite secret-id TTL for secure,
# automated snapshot operations.
#
# CONTEXT:
# Automating Vault Raft snapshots requires appropriate permissions. Instead of
# creating tokens directly, this script establishes a more secure authentication
# method using AppRole, which allows for secret rotation without changing automation.
#
# WORKFLOW:
# 1. Creates a policy with permissions needed for Raft snapshots
# 2. Enables AppRole auth method (if not already enabled)
# 3. Creates a dedicated AppRole with the snapshot policy
# 4. Configures the AppRole with infinite secret-id TTL
# 5. Outputs the role-id and instructions for obtaining a secret-id
#
# REQUIREMENTS:
# - Active Vault session with admin permissions
# - VAULT_ADDR environment variable set to your Vault server
##############################################################################

# ANSI color codes for better terminal output readability
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# ----------------------------------------------------------------------------
# Validation - Check Vault connectivity and token permissions
# ----------------------------------------------------------------------------
echo -e "\n${BLUE}=== Vault Raft Snapshot Policy and AppRole Setup ===${NC}"

# Check if VAULT_ADDR is set
if [ -z "$VAULT_ADDR" ]; then
    echo -e "${RED}Error: VAULT_ADDR environment variable is not set.${NC}"
    echo "Please set the VAULT_ADDR environment variable to your Vault server address."
    echo "Example: export VAULT_ADDR=http://127.0.0.1:8200"
    exit 1
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

# Verify Vault connectivity
echo "Checking Vault connectivity..."
if ! vault status &>/dev/null; then
    echo -e "${RED}Error: Cannot connect to Vault server at $VAULT_ADDR${NC}"
    echo "Please check the server address and network connectivity."
    exit 1
fi

echo "Vault connection successful!"

# ----------------------------------------------------------------------------
# Policy Creation - Define and create policy for Raft snapshots
# ----------------------------------------------------------------------------
echo -e "\n${GREEN}Creating Raft snapshot policy...${NC}"

POLICY_NAME="raft-snapshot-policy"
POLICY_FILE="/tmp/raft-snapshot-policy.hcl"

# Create policy file
cat > "$POLICY_FILE" << EOF
# Raft Snapshot Policy
# Created: $(date)
# Purpose: Allows taking Vault Raft snapshots

# Grant permissions to read snapshots
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}

# Grant permissions for forcing snapshots
path "sys/storage/raft/snapshot-force" {
  capabilities = ["read"]
}

# Additional paths that might be needed for full snapshot functionality
path "sys/storage/raft/*" {
  capabilities = ["read", "list"]
}
EOF

# Write policy to Vault
echo "Writing policy $POLICY_NAME to Vault..."
if ! vault policy write "$POLICY_NAME" "$POLICY_FILE"; then
    echo -e "${RED}Error: Failed to create policy in Vault.${NC}"
    rm "$POLICY_FILE"
    exit 1
fi

echo -e "${GREEN}Policy $POLICY_NAME created successfully!${NC}"
rm "$POLICY_FILE"

# ----------------------------------------------------------------------------
# AppRole Setup - Configure AppRole auth method with infinite TTL
# ----------------------------------------------------------------------------
echo -e "\n${GREEN}Setting up AppRole authentication method...${NC}"

# Enable AppRole auth method if not already enabled
echo "Checking if AppRole auth method is enabled..."
if ! vault auth list | grep -q "approle/"; then
    echo "Enabling AppRole authentication method..."
    if ! vault auth enable approle; then
        echo -e "${RED}Error: Failed to enable AppRole authentication method.${NC}"
        exit 1
    fi
    echo "AppRole authentication method enabled."
else
    echo "AppRole authentication method is already enabled."
fi

# Create AppRole for Raft snapshots
ROLE_NAME="raft-snapshot-role"

echo "Creating AppRole $ROLE_NAME with the $POLICY_NAME policy..."
if ! vault write auth/approle/role/$ROLE_NAME \
    policies=$POLICY_NAME \
    token_ttl=1h \
    token_max_ttl=24h \
    secret_id_ttl=0; then
    echo -e "${RED}Error: Failed to create AppRole.${NC}"
    exit 1
fi

echo -e "${GREEN}AppRole $ROLE_NAME created successfully!${NC}"

# Retrieve and display the Role ID
echo "Retrieving Role ID..."
ROLE_ID=$(vault read -format=json auth/approle/role/$ROLE_NAME/role-id | jq -r '.data.role_id')
if [ -z "$ROLE_ID" ]; then
    echo -e "${RED}Error: Failed to retrieve Role ID.${NC}"
    exit 1
fi

# ----------------------------------------------------------------------------
# Summary and Instructions - Provide next steps
# ----------------------------------------------------------------------------
echo -e "\n${GREEN}====== Vault Raft Snapshot Policy and AppRole Setup Complete ======${NC}"
echo -e "\n${BLUE}Summary:${NC}"
echo "1. Created policy '$POLICY_NAME' with permissions for Raft snapshots"
echo "2. Enabled AppRole authentication method (if not already enabled)"
echo "3. Created AppRole '$ROLE_NAME' with the snapshot policy"
echo "4. Configured AppRole with infinite secret-id TTL"

echo -e "\n${YELLOW}Important Information - SAVE THIS:${NC}"
echo -e "${BLUE}Role ID:${NC} $ROLE_ID"
echo -e "\n${BLUE}To generate a Secret ID:${NC}"
echo "vault write -f auth/approle/role/$ROLE_NAME/secret-id"

echo -e "\n${BLUE}To authenticate using the AppRole:${NC}"
echo "1. export VAULT_ROLE_ID=$ROLE_ID"
echo "2. export VAULT_SECRET_ID=<your-secret-id>"
echo "3. vault write -format=json auth/approle/login role_id=\$VAULT_ROLE_ID secret_id=\$VAULT_SECRET_ID | jq -r '.auth.client_token' > /etc/vault/vault-token"

echo -e "\n${BLUE}For scripts to use this token:${NC}"
echo "export VAULT_TOKEN=\$(cat /etc/vault/vault-token)"
echo -e "\n${YELLOW}Note:${NC} The secret ID never expires, but the token it generates will have a TTL of 1 hour"
echo "with a maximum renewal period of 24 hours. You may want to periodically regenerate"
echo "tokens in your automation."

echo -e "\n${GREEN}Configuration complete!${NC}" 