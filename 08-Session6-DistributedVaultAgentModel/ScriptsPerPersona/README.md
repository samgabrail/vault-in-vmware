# Distributed Vault Agent Per-Application Isolation Model

This guide demonstrates a production-ready approach for managing Vault Agents with complete isolation between applications using a distributed responsibility model.

## Architecture Overview

In this architecture, each application has its own dedicated Vault Agent that:
- Handles authentication via AppRole
- Maintains the Vault token lifecycle
- Writes a token to a file sink that the application can read
- Operates in a "token-only" mode (without providing a local API endpoint)

This model provides strong isolation between applications while maintaining a simplified user management approach, focusing on secure token delivery rather than proxying Vault API calls.

## Responsibility Model

The implementation follows a clear separation of responsibilities across three key personas:

### 1. Vault Administrator (IT Security)
Responsible for Vault server configuration:
- Creating policies for each application
- Setting up AppRoles with appropriate permissions
- Creating the restart AppRole for system administrators
- Maintaining the Vault server and security policies

### 2. System Administrator
Responsible for configuring the application servers:
- Setting up Vault Agent services on application servers
- Managing systemd services and file permissions
- Securely storing the restart AppRole credentials
- Maintaining the infrastructure supporting the applications
- Configuring Secret ID renewal via cron jobs

### 3. Application Teams
Responsible for consuming the provided tokens:
- Reading the token from the file sink path
- Using the token to authenticate with Vault
- Retrieving application-specific secrets
- Implementing proper error handling and fallbacks

## Implementation Scripts

The implementation is split into multiple scripts:

1. **[vault-admin-setup.sh](vault-admin-setup.sh)**: Used by Vault Administrators to configure the Vault server.
2. **[sysadmin-setup.sh](sysadmin-setup.sh)**: Used by System Administrators to set up Vault Agent services on application servers.
3. **[demo-app-secret.sh](demo-app-secret.sh)**: Used to demonstrate how an application would use the token to access secrets.

### Detailed Script Descriptions

#### vault-admin-setup.sh

This script is run by IT Security personnel who administer the Vault server. It handles:

1. **Initial Vault Configuration**:
   - Setting up policies for each application
   - Creating application-specific AppRoles
   - Setting up the restart AppRole (used by SysAdmins)
   - Enabling necessary authentication methods

2. **Policy Management**:
   - Creates limited-scope policies for each application
   - Each policy grants access only to that application's secrets
   - Creates a special policy for the restart AppRole with minimal permissions

3. **AppRole Configuration**:
   - Creates AppRoles with specific TTLs and configurations:
     - Secret ID TTL: 24 hours by default
     - Token TTL: 5 hours by default
     - Maximum token TTL: 24 hours
     - Secret ID usage limit: 150 uses
   - Sets up a restart AppRole with an infinite TTL for service management

4. **Secrets Generation**:
   - Creates sample secrets for each application
   - Supports either default sample secrets or custom key-value pairs
   - Uses Vault's KV v2 secrets engine

5. **Credential Delivery**:
   - Generates restart AppRole credentials
   - Outputs credentials for secure transfer to System Administrators
   - Optionally saves credentials to a JSON file for transfer

**Usage**:
- Run by Vault Administrators when setting up new applications
- Can be run in three modes:
  1. Set up restart AppRole only
  2. Set up application AppRoles only
  3. Complete setup (both)

#### sysadmin-setup.sh

This script is run by System Administrators who manage application servers. It handles:

1. **User and Directory Setup**:
   - Creates the `vaultagent` system user for running Vault Agents
   - Creates the `springApps` user for running applications
   - Sets up the necessary directory structure
   - Configures proper file permissions

2. **Vault Agent Configuration**:
   - Creates configuration files for each application's Vault Agent
   - Sets up token sink files for applications to read
   - Configures Vault Agent in token-only mode (no listener)
   - Creates startup scripts for obtaining role IDs and wrapped secret IDs

3. **Systemd Integration**:
   - Creates systemd service files for each Vault Agent
   - Enables and configures service dependencies
   - Sets up automatic restart capabilities

4. **Secret ID Renewal**:
   - Creates a renewal script that refreshes Secret IDs before expiration
   - Sets up a cron job to run this script periodically
   - Configures proper log files and error handling for the renewal process

5. **Permission Management**:
   - Sets appropriate permissions on all files
   - Ensures token files are owned by `vaultagent:springApps` with mode 440
   - Verifies and fixes permissions as needed

**Usage**:
- Run by System Administrators when:
  1. Setting up a new application server
  2. Adding new applications to an existing server
  3. Updating configurations for existing applications

**Key Features**:
- Idempotent: Can safely be run multiple times
- Supports adding new applications without disrupting existing ones
- Configures automated Secret ID renewal
- Provides detailed feedback and monitoring

#### demo-app-secret.sh

This script demonstrates how applications retrieve secrets using the token provided by Vault Agent. It:

1. **Token Retrieval**:
   - Locates and reads the token from the token sink file
   - Validates that the token exists and is readable

2. **Secret Access**:
   - Makes API calls to Vault using curl
   - Authenticates with the token
   - Retrieves application-specific secrets
   - Formats and displays the results

3. **Error Handling**:
   - Checks for missing tokens
   - Handles permission issues
   - Validates Vault server responses
   - Provides helpful troubleshooting information

**Usage**:
- Run to verify that the tokens are working correctly
- Serves as an example for application developers
- Supports custom secret paths and Vault addresses
- Can be run as root or as the `springApps` user

## Prerequisites

- Linux environment (Ubuntu/Debian recommended)
- Vault CLI installed
- `jq` for JSON parsing
- `curl` for API requests
- Root/sudo access (required for systemd operations)
- A running Vault server

## Secret ID Renewal Mechanism

The Secret ID renewal process is a critical component of this architecture:

### Why Renewal is Necessary
- Application Secret IDs expire after 24 hours by default (configured in vault-admin-setup.sh)
- Without renewal, Vault Agents would lose authentication capabilities
- Renewal ensures continuous operation without manual intervention

### How Renewal Works
1. **Renewal Script**: A dedicated script in `/etc/vault-agents/refresh-secret-ids.sh`:
   - Authenticates to Vault using the restart AppRole credentials
   - Identifies all configured applications
   - For each application:
     - Verifies or retrieves the role ID
     - Generates a new wrapped secret ID
     - Updates permissions for secure storage
   - Logs all activities to `/var/log/vault-agent-renewal.log`

2. **Cron Job Scheduling**:
   - The renewal cron job runs at configurable intervals:
     - Every 8 hours (recommended for 24-hour TTL)
     - Every 12 hours (also good for 24-hour TTL)
     - Daily (cutting it close for 24-hour TTL)
     - Custom schedules available for specific needs
   - The job is stored in `/etc/cron.d/vault-agent-renewal`
   - Runs as root with appropriate permissions

3. **Idempotent Operation**:
   - Can safely run even if the Secret IDs aren't near expiration
   - Properly handles error conditions
   - Maintains file permissions across renewals

4. **Monitoring and Logging**:
   - Records all actions to the renewal log
   - Logs successes and failures for auditing
   - Allows tracking renewal patterns and issues

### Configuring Renewal Frequency
- The renewal frequency should always be less than the Secret ID TTL
- For the default 24-hour TTL, running every 8 hours is recommended
- When modifying TTLs in `vault-admin-setup.sh`, ensure corresponding adjustment of the cron schedule

## Workflow for Adding a New Application

### Step 1: Vault Administrator
1. Run the `vault-admin-setup.sh` script
2. Enter the new application name when prompted
3. Create appropriate policies for the application
4. Set up the AppRole for the application
5. Configure appropriate TTLs for Secret IDs and tokens
6. Securely share restart AppRole credentials with System Administrators

### Step 2: System Administrator
1. Run the `sysadmin-setup.sh` script on the application server
2. Enter the restart AppRole credentials provided by the Vault Administrator
3. Specify the application name to configure
4. Configure Secret ID renewal frequency based on TTL settings
5. Validate that Vault Agent services are running correctly
6. Share token file paths with application teams

### Step 3: Testing the Setup
1. Use the `demo-app-secret.sh` script to verify that the token can be used to access secrets
2. Integrate the token into actual applications by following the same pattern

## Testing with demo-app-secret.sh

The `demo-app-secret.sh` script demonstrates how an application would use the token to access secrets from Vault. This script:

1. Reads the token from the token sink file for a specified application
2. Uses curl to make a request to Vault with the token
3. Retrieves and displays the secret

### Usage

```bash
# Basic usage (default paths)
sudo ./demo-app-secret.sh app1

# Custom Vault address
sudo ./demo-app-secret.sh --addr http://vault.example.com:8200 app1

# Custom secret path
sudo ./demo-app-secret.sh --path secret/data/app1/credentials app1

# Get help
./demo-app-secret.sh --help
```

### Running as Different Users

The script needs to be able to read the token files, which are typically owned by `vaultagent:springApps` with `440` permissions. You can run it as:

1. Root user (has access to all files):
   ```bash
   sudo ./demo-app-secret.sh app1
   ```

2. The springApps user (has group read access to the token):
   ```bash
   sudo -u springApps ./demo-app-secret.sh app1
   ```

### Example Output

```
=== Demo: Accessing Vault Secret with Token ===
Application: app1
Secret Path: secret/data/app1/config
Vault Server: http://127.0.0.1:8200

Reading token from /home/springApps/.vault-tokens/app1-token...
Token: hvs.CAESI0... (truncated for security)

Retrieving secret from Vault...
Command: curl -s -H "X-Vault-Token: $TOKEN" http://127.0.0.1:8200/v1/secret/data/app1/config

Secret retrieved successfully:
{
  "api-key": "app1-secret-key",
  "db-password": "app1-db-password"
}

=== Demo Complete ===
This demonstrates that:
1. The token was successfully created by the Vault Agent
2. The token has the correct permissions to access the secret
3. The application can use this token to authenticate to Vault

In a real application, this token would be used similarly to access secrets programmatically.
```

## Key Security Features

### AppRole Authentication

- Each application has its own AppRole with tightly scoped permissions
- SecretIDs are wrapped to enhance security during delivery
- A dedicated restart AppRole with minimal permissions for service startup

### Wrapped Secret IDs

Instead of storing secret IDs directly:
1. The agent startup script authenticates using the restart AppRole
2. It fetches the role-id for the application
3. It requests a wrapped secret ID for the specific application
4. Both credentials are stored temporarily and securely
5. The Vault Agent consumes these credentials during startup

### Systemd Integration

Each Vault Agent has:
1. Its own systemd unit file
2. Startup scripts that run to gather necessary credentials
3. Automatic restart capabilities
4. Proper service dependency management

### File Organization

All files follow a consistent naming convention:
- `/etc/vault-agents/{app_name}/role-id`: Stores the role ID for each application
- `/etc/vault-agents/{app_name}/wrapped-secret-id`: Temporarily stores wrapped secret IDs
- `/home/springApps/.vault-tokens/{app_name}-token`: The token sink for applications to use

## Token-Only Mode

This implementation uses Vault Agent in "token-only" mode:
- No listener stanza in the configuration
- Applications interact directly with the Vault server using the token
- The Vault Agent only handles authentication and token renewal
- The token is written to a file sink that the application reads
- This approach simplifies the configuration and reduces the attack surface

## Script Interactions and Dependencies

The three scripts work together in sequence to create a complete management system:

1. **vault-admin-setup.sh**:
   - Creates the necessary policies and AppRoles in Vault
   - Outputs restart AppRole credentials for SysAdmins
   - Sets fundamental TTL configurations that affect renewal requirements

2. **sysadmin-setup.sh**:
   - Uses the restart AppRole credentials from vault-admin-setup.sh
   - Creates Vault Agent configurations and services
   - Sets up a Secret ID renewal system based on TTLs
   - Outputs token file paths for application teams

3. **demo-app-secret.sh**:
   - Uses the tokens created by Vault Agents
   - Demonstrates how applications should interact with Vault
   - Validates that the authentication chain is working correctly

This workflow ensures clear separation of duties while maintaining security throughout the process.

## Benefits of This Approach

1. **Complete Isolation**: Each application only has access to its own secrets.
2. **Simplified Authentication**: Applications don't need to handle AppRole authentication logic.
3. **Clear Responsibility Model**: Well-defined roles for different teams.
4. **Scalability**: Easy to add new applications to the system.
5. **Security**: Minimal permissions for each component and secure credential delivery.
6. **Simplified User Management**: Using a single Linux user for all applications reduces complexity while maintaining security through AppRole isolation.
7. **Reduced Attack Surface**: By using token-only mode, we eliminate the need for a local agent API endpoint.
8. **Automated Credential Rotation**: Secret IDs are automatically refreshed before expiration.
9. **Idempotent Operations**: Scripts can be safely run multiple times without breaking the system.

## File Permissions and Security Considerations

- Vault Agent runs as the dedicated `vaultagent` system user
- Applications run as the `springApps` user
- Token files are owned by `vaultagent` with group access for `springApps`
- AppRole credentials are stored with restrictive permissions
- Secret ID renewal operates via root cronjob with secure file access
- Systemd services run with appropriate privileges

## Application Integration Pattern

Applications should follow this pattern to access secrets:

```python
# Python example
import os
import requests

# Token path provided by SysAdmin
TOKEN_PATH = '/home/springApps/.vault-tokens/app1-token'
VAULT_ADDR = 'http://vault.example.com:8200'

# Read the token
with open(TOKEN_PATH, 'r') as f:
    vault_token = f.read().strip()

# Use the token to authenticate with Vault
headers = {'X-Vault-Token': vault_token}
response = requests.get(f'{VAULT_ADDR}/v1/secret/data/app1/config', headers=headers)

# Get the secret
if response.status_code == 200:
    secret_data = response.json()['data']['data']
    api_key = secret_data['api-key']
    db_password = secret_data['db-password']
```

## Troubleshooting

### Vault Agent Service Issues
```bash
# Check service status
sudo systemctl status vault-agent-<application>

# View service logs
sudo journalctl -u vault-agent-<application>

# Restart a service
sudo systemctl restart vault-agent-<application>
```

### Token File Issues
```bash
# Check file existence
ls -la /home/springApps/.vault-tokens/<application>-token

# Check file permissions
stat -c '%a %U:%G' /home/springApps/.vault-tokens/<application>-token

# Fix file permissions
sudo chown vaultagent:springApps /home/springApps/.vault-tokens/<application>-token
sudo chmod 440 /home/springApps/.vault-tokens/<application>-token
```

### Secret ID Renewal Issues
```bash
# Check renewal log
sudo cat /var/log/vault-agent-renewal.log

# Check cron configuration
sudo cat /etc/cron.d/vault-agent-renewal

# Run the renewal script manually to verify it works
sudo /etc/vault-agents/refresh-secret-ids.sh

# Verify permissions on the renewal script
sudo stat -c '%a %U:%G' /etc/vault-agents/refresh-secret-ids.sh
```

## Support and Maintenance

- **Vault Administration**: Security team should regularly review and audit policies and AppRoles
- **System Administration**: 
  - Monitor Vault Agent services and ensure they're running properly
  - Check renewal logs periodically to verify Secret ID rotation
  - Review cron job status and ensure it's executing as expected
- **Application Teams**: Ensure proper error handling and fallback mechanisms in applications

## Cleanup Instructions

When you need to remove an application:

1. **Vault Administrator**:
   ```bash
   # Remove the AppRole
   vault delete auth/approle/role/<application>
   
   # Remove the policy
   vault policy delete <application>
   
   # Remove the secrets
   vault kv metadata delete secret/<application>/config
   ```

2. **System Administrator**:
   ```bash
   # Stop and disable the service
   sudo systemctl stop vault-agent-<application>
   sudo systemctl disable vault-agent-<application>
   
   # Remove the service file and configuration
   sudo rm /etc/systemd/system/vault-agent-<application>.service
   sudo rm -rf /etc/vault-agents/<application>
   sudo rm /etc/vault-agents/<application>-agent.hcl
   sudo rm /etc/vault-agents/<application>-agent-start.sh
   
   # Remove the token file
   sudo rm /home/springApps/.vault-tokens/<application>-token
   
   # Reload systemd
   sudo systemctl daemon-reload
   ```