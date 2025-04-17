# Vault Agent Per-Application Isolation Demo

This guide demonstrates how to set up dedicated Vault Agents for each application, providing maximum isolation and security separation. In this approach, each Vault Agent handles authentication only, and applications use the resulting tokens to access their secrets directly from Vault.

## Demo Overview

The `run-demo.sh` script in this directory demonstrates the following:

1. **Per-Application Authentication**: Each application gets its own dedicated Vault Agent with its own AppRole credentials
2. **No Templates**: Vault Agent is used only for authentication, not for secret retrieval or template rendering
3. **Application-Driven Secret Access**: Applications retrieve secrets directly from Vault using the token provided by their Agent
4. **Complete Isolation**: Each application can only access its designated secrets

## Prerequisites

- Linux environment (Ubuntu/Debian recommended)
- Vault CLI installed
- `jq` for JSON parsing
- Python 3 with the `requests` module for the demo scripts

## How the Demo Works

The `run-demo.sh` script performs the following steps:

1. **Sets up a Vault Dev Server**: Waits for you to start a Vault dev server in a separate terminal
2. **Creates Application-Specific Policies**:
   - `app1-policy`: Allows access only to `secret/data/app1/*`
   - `app2-policy`: Allows access only to `secret/data/app2/*`
3. **Creates Sample Secrets**:
   - `secret/app1/config`: Contains credentials for app1
   - `secret/app2/config`: Contains credentials for app2
4. **Configures AppRole Authentication**:
   - Creates a separate AppRole for each application
   - Each AppRole is tied to its application-specific policy
   - Generates role-ids and secret-ids for each AppRole
5. **Creates Separate Vault Agent Configurations**:
   - Each application gets a dedicated Vault Agent config file
   - Each Agent authenticates using the appropriate AppRole
   - Agents write tokens to application-specific sink files
6. **Starts Separate Vault Agents**:
   - One Agent for app1
   - One Agent for app2
7. **Creates Test Applications**:
   - Python scripts that demonstrate fetching secrets using the tokens
   - Shows proper access control (each application can only access its own secrets)
8. **Cleans Up**: Terminates Agents and removes temporary files

## Running the Demo

To run the demo:

1. Open two terminal windows
2. In the first window, start Vault in dev mode:
   ```bash
   vault server -dev -dev-root-token-id="root"
   ```
3. In the second window, run the demo script:
   ```bash
   ./run-demo.sh
   ```
4. Follow the prompts in the script

The script will:
- Create all necessary configurations
- Start two separate Vault Agents
- Run test scripts that demonstrate accessing secrets
- Show that each application can only access its own secrets

## Application Code Examples

The demo includes Python and shell script examples showing how applications would retrieve secrets:

### Python Example

```python
#!/usr/bin/env python3
import requests
import json

# Path where Vault Agent saves the token
TOKEN_PATH = '/tmp/app1/vault-token'
VAULT_ADDR = 'http://127.0.0.1:8200'

# Read the token from the file created by Vault Agent
with open(TOKEN_PATH, 'r') as f:
    vault_token = f.read().strip()

# Set up headers with the Vault token
headers = {
    'X-Vault-Token': vault_token
}

# Retrieve secrets from Vault using the token
response = requests.get(
    f'{VAULT_ADDR}/v1/secret/data/app1/config', 
    headers=headers
)

if response.status_code == 200:
    secrets = response.json()['data']['data']
    print(f"API Key: {secrets['api-key']}, DB Password: {secrets['db-password']}")
    
    # Now the application can use these secrets
    # db_connection = connect_to_db(username="app1_user", password=secrets['db-password'])
    # api_client = APIClient(api_key=secrets['api-key'])
else:
    print(f"Failed to retrieve secrets: {response.status_code}, {response.text}")
```

### Bash Example

```bash
#!/bin/bash

# Path where Vault Agent saves the token
TOKEN_PATH="/tmp/app1/vault-token"
VAULT_ADDR="http://127.0.0.1:8200"

# Read the token from the file created by Vault Agent
VAULT_TOKEN=$(cat $TOKEN_PATH)

# Retrieve secrets from Vault using the token
RESPONSE=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/secret/data/app1/config)
API_KEY=$(echo $RESPONSE | jq -r '.data.data.api-key')
DB_PASSWORD=$(echo $RESPONSE | jq -r '.data.data.db-password')

echo "Retrieved secrets for app1:"
echo "API Key: $API_KEY"
echo "DB Password: $DB_PASSWORD"

# Now the application can use these secrets
# db_connect --user app1_user --password "$DB_PASSWORD"
# api_call --key "$API_KEY" --endpoint "/some/endpoint"
```

## Benefits of This Approach

1. **Complete Isolation**: Each application has its own Vault Agent running with its specific AppRole credentials, ensuring one application cannot access another's secrets.

2. **Simplified Authentication**: Each agent authenticates using AppRole and provides a token for the application to use.

3. **Application Control**: Applications have full control over when and how to fetch secrets using the token, which can be beneficial for:
   - Fetching secrets on demand rather than at startup
   - Implementing custom caching strategies
   - Handling secret rotation logic within the application

4. **Easy Integration**: Works with existing application code that knows how to communicate with Vault's API.

## Production Considerations

1. **Security Hardening**:
   - Use TLS for Vault communication
   - Run each Vault Agent as a different user with minimal permissions
   - Set appropriate permissions on token files so only the application can read them
   - Consider using memory-based filesystems for token storage in sensitive environments

2. **Token Management**:
   - Applications should handle token renewal or failure gracefully
   - Set appropriate token TTLs based on your security requirements
   - Consider implementing token rotation strategies

3. **High Availability**:
   - Set up each Vault Agent as a systemd service with automatic restarts
   - Implement monitoring for each agent separately
   - Applications should handle temporary Vault unavailability

4. **Scaling**:
   - For microservice architectures, consider a dedicated Vault Agent per service
   - For large-scale deployments, consider Vault Enterprise for namespaces and additional isolation features
