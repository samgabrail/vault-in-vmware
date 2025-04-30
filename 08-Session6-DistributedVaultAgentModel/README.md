# Vault Agent Per-Application Isolation Demo

This guide demonstrates how to set up dedicated Vault Agents for each application, providing maximum isolation and security separation. In this approach, each Vault Agent handles authentication only, and applications use the resulting tokens to access their secrets directly from Vault.

## Demo Overview

The `run-demo.sh` script demonstrates a production-ready approach for managing Vault Agents with:

1. **Per-Application Authentication**: Each application gets its own dedicated Vault Agent with its own AppRole credentials
2. **Wrapped Secret IDs**: Enhanced security through secret response wrapping
3. **Systemd Integration**: Each Vault Agent runs as a systemd service with proper lifecycle management
4. **Complete Isolation**: Each application can only access its designated secrets
5. **Dynamic Role ID Delivery**: Role IDs are dynamically delivered at service startup
6. **Support for Arbitrary Applications**: The script can be easily modified to support any number of applications

## Prerequisites

- Linux environment (Ubuntu/Debian recommended)
- Vault CLI installed
- `jq` for JSON parsing
- Python 3 with the `requests` module for the demo scripts
- Root/sudo access (required for systemd operations)

## Running the Demo

To run the demo:

1. Open two terminal windows
2. In the first window, start Vault in dev mode:
   ```bash
   vault server -dev -dev-root-token-id="root"
   ```
3. In the second window, run the demo script with sudo:
   ```bash
   sudo ./run-demo.sh
   ```
4. Follow the prompts in the script

## Key Security Features

### Restart AppRole

A dedicated AppRole with the following characteristics:
- Tight permissions: Only allowed to create wrapped secret IDs for application AppRoles and read role-ids
- Long-lived secret ID: Uses an infinite TTL for the secret ID
- Would be delivered by CI/CD system (like Jenkins) in production

### Wrapped Secret IDs

Instead of storing secret IDs directly:
1. The agent startup script authenticates using the restart AppRole
2. It fetches the role-id for the application
3. It requests a wrapped secret ID for the specific application
4. Both credentials are stored temporarily
5. The Vault Agent consumes these credentials securely

### Systemd Integration

Each Vault Agent has:
1. Its own systemd unit file
2. Startup scripts that run to gather the necessary credentials
3. Automatic restart capabilities
4. Proper service dependency management

### File Organization

All files follow a consistent naming convention:
- `/etc/vault-agents/{app_name}/role-id`: Stores the role ID for each application
- `/etc/vault-agents/{app_name}/wrapped-secret-id`: Temporarily stores wrapped secret IDs
- `/etc/vault-agents/{app_name}/vault-token`: The token sink for applications to use

## Customizing for Your Environment

To customize the applications the script configures:

1. Modify the `APP_NAMES` array in the script:
   ```bash
   # List of applications to set up - MODIFY THIS LIST for your environment
   declare -a APP_NAMES=("webapp" "database" "api-service" "background-worker")
   ```

2. Adjust the corresponding listener ports:
   ```bash
   LISTENER_PORTS=(8100 8200 8300 8400) # Corresponding local ports for Vault Agent API endpoints
   ```

## Application Code Examples

The demo includes Python examples showing how applications retrieve secrets:

### Python Example

```python
#!/usr/bin/env python3
import requests
import json

# Path where Vault Agent saves the token
TOKEN_PATH = '/etc/vault-agents/webapp/vault-token'
VAULT_ADDR = 'http://127.0.0.1:8200'
AGENT_ADDR = 'http://127.0.0.1:8100'  # Local Vault Agent API endpoint

# Read the token from the file created by Vault Agent
with open(TOKEN_PATH, 'r') as f:
    vault_token = f.read().strip()

# Set up headers with the Vault token
headers = {
    'X-Vault-Token': vault_token
}

# Option 1: Retrieve secrets directly from Vault
response = requests.get(
    f'{VAULT_ADDR}/v1/secret/data/webapp/config', 
    headers=headers
)

# Option 2: Retrieve through the Vault Agent's cache (more efficient)
# response = requests.get(
#     f'{AGENT_ADDR}/v1/secret/data/webapp/config',
#     headers=headers
# )

if response.status_code == 200:
    secrets = response.json()['data']['data']
    print(f"API Key: {secrets['api-key']}, DB Password: {secrets['db-password']}")
    
    # Now the application can use these secrets
    # db_connection = connect_to_db(username="webapp_user", password=secrets['db-password'])
    # api_client = APIClient(api_key=secrets['api-key'])
else:
    print(f"Failed to retrieve secrets: {response.status_code}, {response.text}")
```

## Benefits of This Approach

1. **Complete Isolation**: Each application has its own Vault Agent running with its specific AppRole credentials, ensuring one application cannot access another's secrets.

2. **Simplified Authentication**: Each agent authenticates using AppRole and provides a token for the application to use.

3. **Application Control**: Applications have full control over when and how to fetch secrets using the token, which can be beneficial for:
   - Fetching secrets on demand rather than at startup
   - Implementing custom caching strategies
   - Handling secret rotation logic within the application

4. **Easy Integration**: Works with existing application code that knows how to communicate with Vault's API.

5. **Enhanced Security**:
   - Wrapped secret IDs are never stored in plaintext for extended periods
   - Systemd handles service restarts and dependencies
   - Clear separation of restart privileges from application privileges
   - Role IDs are dynamically delivered, reducing manual credential handling

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
   - Systemd already provides automatic restarts and supervision
   - Implement monitoring for each agent separately
   - Applications should handle temporary Vault unavailability

4. **CI/CD Integration**:
   - In production, use Jenkins or another CI/CD system to deliver the restart AppRole credentials
   - Keep the restart AppRole's secret ID secure and rotate regularly
   - Consider implementing audit logging for all restart operations
