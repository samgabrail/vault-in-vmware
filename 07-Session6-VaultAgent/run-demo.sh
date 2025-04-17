#!/bin/bash
# Demo script for running separate Vault Agents for each application

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Vault Agent Per-App Isolation Demo ===${NC}"
echo "This script demonstrates using separate Vault Agents for each application to provide complete isolation."

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

echo -e "\n${GREEN}Creating policies...${NC}"
# Create policy for app1
cat > /tmp/app1-policy.hcl << EOF
path "secret/data/app1/*" {
  capabilities = ["read", "list"]
}
EOF

# Create policy for app2
cat > /tmp/app2-policy.hcl << EOF
path "secret/data/app2/*" {
  capabilities = ["read", "list"]
}
EOF

# Apply the policies
vault policy write app1-policy /tmp/app1-policy.hcl
vault policy write app2-policy /tmp/app2-policy.hcl

echo -e "\n${GREEN}Enabling secrets engine...${NC}"
# Enable KV secrets engine
vault secrets enable -version=2 -path=secret kv 2>/dev/null || echo "Secret engine already enabled"

echo -e "\n${GREEN}Creating sample secrets...${NC}"
# Create sample secrets
vault kv put secret/app1/config api-key="app1-secret-key" db-password="app1-db-password"
vault kv put secret/app2/config api-key="app2-secret-key" db-password="app2-db-password"

echo -e "\n${GREEN}Setting up AppRole authentication for each application...${NC}"
# Enable AppRole auth method
vault auth enable approle 2>/dev/null || echo "AppRole already enabled"

# Create AppRole for app1
vault write auth/approle/role/app1-role \
    token_policies="app1-policy" \
    token_ttl=1h \
    token_max_ttl=4h

# Create AppRole for app2
vault write auth/approle/role/app2-role \
    token_policies="app2-policy" \
    token_ttl=1h \
    token_max_ttl=4h

# Get role-id and secret-id for app1
vault read -format=json auth/approle/role/app1-role/role-id | jq -r '.data.role_id' > /tmp/app1-role-id
vault write -f -format=json auth/approle/role/app1-role/secret-id | jq -r '.data.secret_id' > /tmp/app1-secret-id

# Get role-id and secret-id for app2
vault read -format=json auth/approle/role/app2-role/role-id | jq -r '.data.role_id' > /tmp/app2-role-id
vault write -f -format=json auth/approle/role/app2-role/secret-id | jq -r '.data.secret_id' > /tmp/app2-secret-id

# Set proper permissions
chmod 600 /tmp/app1-role-id /tmp/app1-secret-id /tmp/app2-role-id /tmp/app2-secret-id

echo -e "\n${GREEN}Creating temporary directories...${NC}"
# Create directories for testing
mkdir -p /tmp/app1
mkdir -p /tmp/app2

# Create Vault Agent configuration for app1
cat > /tmp/app1-agent.hcl << EOF
exit_after_auth = false
pid_file = "/tmp/vault-agent-app1.pid"

vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "/tmp/app1-role-id"
      secret_id_file_path = "/tmp/app1-secret-id"
    }
  }

  sink "file" {
    config = {
      path = "/tmp/app1/vault-token"
      mode = 0440
    }
  }
}
EOF

# Create Vault Agent configuration for app2
cat > /tmp/app2-agent.hcl << EOF
exit_after_auth = false
pid_file = "/tmp/vault-agent-app2.pid"

vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "/tmp/app2-role-id"
      secret_id_file_path = "/tmp/app2-secret-id"
    }
  }

  sink "file" {
    config = {
      path = "/tmp/app2/vault-token"
      mode = 0440
    }
  }
}
EOF

echo -e "\n${GREEN}Starting Vault Agents...${NC}"
echo "Running Vault Agent for app1 in the background..."
vault agent -log-level=info -config=/tmp/app1-agent.hcl > /tmp/app1-agent.log 2>&1 &
APP1_AGENT_PID=$!

echo "Running Vault Agent for app2 in the background..."
vault agent -log-level=info -config=/tmp/app2-agent.hcl > /tmp/app2-agent.log 2>&1 &
APP2_AGENT_PID=$!

# Wait for tokens to be created
echo "Waiting for tokens to be created..."
sleep 5

# Check if tokens were created
if [ -f "/tmp/app1/vault-token" ] && [ -f "/tmp/app2/vault-token" ]; then
    echo -e "${GREEN}Tokens created successfully!${NC}"
else
    echo -e "${RED}Error: Tokens were not created.${NC}"
    echo "Check the agent logs at /tmp/app1-agent.log and /tmp/app2-agent.log"
    cat /tmp/app1-agent.log
    cat /tmp/app2-agent.log
    kill $APP1_AGENT_PID $APP2_AGENT_PID 2>/dev/null
    exit 1
fi

echo -e "\n${GREEN}Creating simple test scripts...${NC}"
# Create a Python script for app1
cat > /tmp/app1-script.py << EOF
#!/usr/bin/env python3
import os
import requests
import json

TOKEN_PATH = '/tmp/app1/vault-token'
VAULT_ADDR = 'http://127.0.0.1:8200'

# Read the token
with open(TOKEN_PATH, 'r') as f:
    vault_token = f.read().strip()

# Set up headers
headers = {
    'X-Vault-Token': vault_token
}

# Get secrets
response = requests.get(
    f'{VAULT_ADDR}/v1/secret/data/app1/config', 
    headers=headers
)

print(f"App1 retrieving secrets:")
if response.status_code == 200:
    secrets = response.json()['data']['data']
    print(f"  API Key: {secrets['api-key']}")
    print(f"  DB Password: {secrets['db-password']}")
else:
    print(f"  Error: {response.status_code}")
    print(f"  Response: {response.text}")

# Attempt to access app2 secrets (should fail)
print("App1 attempting to access app2 secrets (should fail):")
response = requests.get(
    f'{VAULT_ADDR}/v1/secret/data/app2/config', 
    headers=headers
)
if response.status_code != 200:
    print(f"  Access correctly denied: {response.status_code}")
else:
    print(f"  ERROR: Access incorrectly granted to app2 secrets!")
EOF

# Create a Python script for app2
cat > /tmp/app2-script.py << EOF
#!/usr/bin/env python3
import os
import requests
import json

TOKEN_PATH = '/tmp/app2/vault-token'
VAULT_ADDR = 'http://127.0.0.1:8200'

# Read the token
with open(TOKEN_PATH, 'r') as f:
    vault_token = f.read().strip()

# Set up headers
headers = {
    'X-Vault-Token': vault_token
}

# Get secrets
response = requests.get(
    f'{VAULT_ADDR}/v1/secret/data/app2/config', 
    headers=headers
)

print(f"App2 retrieving secrets:")
if response.status_code == 200:
    secrets = response.json()['data']['data']
    print(f"  API Key: {secrets['api-key']}")
    print(f"  DB Password: {secrets['db-password']}")
else:
    print(f"  Error: {response.status_code}")
    print(f"  Response: {response.text}")

# Attempt to access app1 secrets (should fail)
print("App2 attempting to access app1 secrets (should fail):")
response = requests.get(
    f'{VAULT_ADDR}/v1/secret/data/app1/config', 
    headers=headers
)
if response.status_code != 200:
    print(f"  Access correctly denied: {response.status_code}")
else:
    print(f"  ERROR: Access incorrectly granted to app1 secrets!")
EOF

chmod +x /tmp/app1-script.py
chmod +x /tmp/app2-script.py

echo -e "\n${GREEN}Testing application access with tokens...${NC}"
echo -e "\n${BLUE}Running app1 script:${NC}"
python3 /tmp/app1-script.py

echo -e "\n${BLUE}Running app2 script:${NC}"
python3 /tmp/app2-script.py

echo -e "\n${GREEN}Manually verifying tokens...${NC}"
echo -e "\n${BLUE}App1 token info:${NC}"
export APP1_TOKEN=$(cat /tmp/app1/vault-token)
VAULT_TOKEN=$APP1_TOKEN vault token lookup | grep policies

echo -e "\n${BLUE}App2 token info:${NC}"
export APP2_TOKEN=$(cat /tmp/app2/vault-token)
VAULT_TOKEN=$APP2_TOKEN vault token lookup | grep policies

echo -e "\n${GREEN}Demo completed successfully!${NC}"
echo "Cleaning up..."

# Kill the Vault Agents
kill $APP1_AGENT_PID $APP2_AGENT_PID 2>/dev/null

# Clean up test files
echo -e "\n${GREEN}Removing temporary files...${NC}"
rm -rf /tmp/app1 /tmp/app2
rm -f /tmp/app1-role-id /tmp/app1-secret-id /tmp/app2-role-id /tmp/app2-secret-id
rm -f /tmp/app1-agent.hcl /tmp/app2-agent.hcl
rm -f /tmp/app1-policy.hcl /tmp/app2-policy.hcl
rm -f /tmp/app1-script.py /tmp/app2-script.py
rm -f /tmp/app1-agent.log /tmp/app2-agent.log
rm -f /tmp/vault-agent-app1.pid /tmp/vault-agent-app2.pid

echo -e "\n${BLUE}=== Demo Complete ===${NC}"
echo "You should now stop the Vault dev server in the other terminal." 