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

## Cleanup Instructions

When you're done with the demo, you can clean up everything with these commands:

```bash
./clean-demo.sh
```

If you added additional applications to the configuration, make sure to include them in the cleanup commands as well.

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
   LISTENER_PORTS=(8007 8008 8009 8010) # Corresponding local ports for Vault Agent API endpoints
   ```


## Benefits of This Approach

1. **Complete Isolation**: Each application has its own Vault Agent running with its specific AppRole credentials, ensuring one application cannot access another's secrets.

2. **Simplified Authentication**: Each agent authenticates using AppRole and provides a token for the application to use.

3. **Application Control**: Applications have full control over when and how to fetch secrets using the token, which can be beneficial for:
   - Fetching secrets on demand rather than at startup
   - Handling secret rotation logic within the application

4. **Easy Integration**: Works with existing application code that knows how to communicate with Vault's API.

5. **Enhanced Security**:
   - Wrapped secret IDs are never stored in plaintext for extended periods
   - Systemd handles service restarts and dependencies
   - Clear separation of restart privileges from application privileges
   - Role IDs are dynamically delivered, reducing manual credential handling


## Demo Results

### File Permissions and Ownerships

```bash
# This is where you will store your application, each app will have its own user and home directory
root@docker-1:/home/webapp_user/scripts# ll
total 12
drwxr-xr-x 2 webapp_user webapp_user 4096 Apr 30 19:36 ./
drwxr-xr-x 3 webapp_user webapp_user 4096 Apr 30 19:36 ../
-rwxr-xr-x 1 webapp_user webapp_user 1733 Apr 30 19:36 webapp-script.py*

root@docker-1:/home/database_user/scripts# ll
total 12
drwxr-xr-x 2 database_user database_user 4096 Apr 30 19:36 ./
drwxr-xr-x 3 database_user database_user 4096 Apr 30 19:36 ../
-rwxr-xr-x 1 database_user database_user 1741 Apr 30 19:36 database-script.py*


# This is where we store the config for the vault agents
root@docker-1:/etc/vault-agents# ll
total 60
drwxr-xr-x   4 root       root          4096 Apr 30 17:06 ./
drwxr-xr-x 102 root       root          4096 Apr 30 19:36 ../
drwxr-x---   2 vaultagent database_user 4096 Apr 30 17:11 database/
-rw-r-----   1 vaultagent vaultagent     818 Apr 30 19:36 database-agent.hcl
-rwx------   1 vaultagent vaultagent    1035 Apr 30 19:36 database-agent-start.sh*
-rw-r--r--   1 root       root            68 Apr 30 19:36 database-policy.hcl
-rwxr-xr-x   1 appuser    appuser       1741 Apr 30 17:38 database-script.py*
-rw-r--r--   1 root       root           302 Apr 30 19:36 restart-policy.hcl
-rw-------   1 vaultagent vaultagent      37 Apr 30 19:36 restart-role-id
-rw-------   1 vaultagent vaultagent      37 Apr 30 19:36 restart-secret-id
drwxr-x---   2 vaultagent webapp_user   4096 Apr 30 17:32 webapp/
-rw-r-----   1 vaultagent vaultagent     806 Apr 30 19:36 webapp-agent.hcl
-rwx------   1 vaultagent vaultagent    1025 Apr 30 19:36 webapp-agent-start.sh*
-rw-r--r--   1 root       root            66 Apr 30 19:36 webapp-policy.hcl
-rwxr-xr-x   1 appuser    appuser       1733 Apr 30 17:38 webapp-script.py*

root@docker-1:/etc/vault-agents/webapp# ll
total 20
drwxr-x--- 2 vaultagent webapp_user 4096 Apr 30 17:32 ./
drwxr-xr-x 4 root       root        4096 Apr 30 17:06 ../
-rw------- 1 root       root          36 Apr 30 17:32 role-id
-rw------- 1 root       root           7 Apr 30 17:32 vault-agent.pid
-r--r----- 1 vaultagent webapp_user   95 Apr 30 17:32 vault-token

root@docker-1:/etc/vault-agents/webapp# cd ../database

root@docker-1:/etc/vault-agents/database# ll
total 20
drwxr-x--- 2 vaultagent database_user 4096 Apr 30 17:11 ./
drwxr-xr-x 4 root       root          4096 Apr 30 17:06 ../
-rw------- 1 root       root            36 Apr 30 17:11 role-id
-rw------- 1 root       root             7 Apr 30 17:11 vault-agent.pid
-r--r----- 1 vaultagent database_user   95 Apr 30 17:11 vault-token

root@docker-1:/etc/vault-agents/database# ll /etc/systemd/system/vault-agent-webapp.service
-rw-r--r-- 1 root root 240 Apr 30 19:36 /etc/systemd/system/vault-agent-webapp.service

root@docker-1:/etc/vault-agents/database# ll /etc/systemd/system/vault-agent-database.service
-rw-r--r-- 1 root root 244 Apr 30 19:36 /etc/systemd/system/vault-agent-database.service
```


### Application Scripts

#### Webapp
```python
# root@docker-1:/home/webapp_user/scripts# cat webapp-script.py
#!/usr/bin/env python3
import os
import requests
import json
import time

TOKEN_PATH = '/etc/vault-agents/webapp/vault-token'
VAULT_ADDR = 'http://127.0.0.1:8200'
AGENT_ADDR = 'http://127.0.0.1:8100'

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
    f'{VAULT_ADDR}/v1/secret/data/webapp/config',
    headers=headers
)

# Alternatively, using the Vault Agent API
# response = requests.get(
#     f'{AGENT_ADDR}/v1/secret/data/webapp/config',
#     headers=headers
# )

print(f"webapp retrieving secrets:")
if response.status_code == 200:
    secrets = response.json()['data']['data']
    print(f"  API Key: {secrets['api-key']}")
    print(f"  DB Password: {secrets['db-password']}")
else:
    print(f"  Error: {response.status_code}")
    print(f"  Response: {response.text}")

# Try to access secrets from other apps to test isolation
other_apps = ["database"]
for other_app in other_apps:
    print(f"webapp attempting to access {other_app} secrets (should fail):")
    response = requests.get(
        f'{VAULT_ADDR}/v1/secret/data/{other_app}/config',
        headers=headers
    )
    if response.status_code != 200:
        print(f"  Access correctly denied: {response.status_code}")
    else:
        print(f"  ERROR: Access incorrectly granted to {other_app} secrets!")
```

#### Database

```python
# root@docker-1:/home/database_user/scripts# cat database-script.py
#!/usr/bin/env python3
import os
import requests
import json
import time

TOKEN_PATH = '/etc/vault-agents/database/vault-token'
VAULT_ADDR = 'http://127.0.0.1:8200'
AGENT_ADDR = 'http://127.0.0.1:8200'

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
    f'{VAULT_ADDR}/v1/secret/data/database/config',
    headers=headers
)

# Alternatively, using the Vault Agent API
# response = requests.get(
#     f'{AGENT_ADDR}/v1/secret/data/database/config',
#     headers=headers
# )

print(f"database retrieving secrets:")
if response.status_code == 200:
    secrets = response.json()['data']['data']
    print(f"  API Key: {secrets['api-key']}")
    print(f"  DB Password: {secrets['db-password']}")
else:
    print(f"  Error: {response.status_code}")
    print(f"  Response: {response.text}")

# Try to access secrets from other apps to test isolation
other_apps = ["webapp"]
for other_app in other_apps:
    print(f"database attempting to access {other_app} secrets (should fail):")
    response = requests.get(
        f'{VAULT_ADDR}/v1/secret/data/{other_app}/config',
        headers=headers
    )
    if response.status_code != 200:
        print(f"  Access correctly denied: {response.status_code}")
    else:
        print(f"  ERROR: Access incorrectly granted to {other_app} secrets!")
```

### Systemd Files

#### Webapp

```bash
root@docker-1:/etc/vault-agents/database# cat /etc/systemd/system/vault-agent-webapp.service
[Unit]
Description=Vault Agent for Webapp
After=network.target

[Service]
Type=simple
ExecStart=/etc/vault-agents/webapp-agent-start.sh
Restart=on-failure
RestartSec=10
User=vaultagent
Group=vaultagent

[Install]
WantedBy=multi-user.target
```

#### Database

```bash
root@docker-1:/etc/vault-agents/database# cat /etc/systemd/system/vault-agent-database.service
[Unit]
Description=Vault Agent for Database
After=network.target

[Service]
Type=simple
ExecStart=/etc/vault-agents/database-agent-start.sh
Restart=on-failure
RestartSec=10
User=vaultagent
Group=vaultagent

[Install]
WantedBy=multi-user.target
```

