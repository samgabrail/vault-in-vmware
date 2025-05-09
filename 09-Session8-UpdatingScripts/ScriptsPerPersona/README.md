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
- Configuring Vault Agents with proper exit_on_err settings for automatic renewal

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
4. **[sysadmin-raft-snapshot.sh](sysadmin-raft-snapshot.sh)**: Used to take Vault Raft snapshots for backup and disaster recovery.
5. **[sysadmin-setup-snapshot-cron.sh](sysadmin-setup-snapshot-cron.sh)**: Used by System Administrators to set up a cronjob for regular Raft snapshots.
6. **[sysadmin-raft-restore.sh](sysadmin-raft-restore.sh)**: Used to restore Vault from a Raft snapshot in disaster recovery scenarios.
7. **[vault-admin-configure-autopilot.sh](vault-admin-configure-autopilot.sh)**: Used to configure Vault's Raft autopilot for dead server cleanup.
8. **[vault-admin-enable-audit-logs.sh](vault-admin-enable-audit-logs.sh)**: Used to enable and configure Vault audit logging.

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
   - Configures restart behavior for handling Secret ID expiry

4. **Permission Management**:
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
- Configures automated Secret ID renewal via systemd restart
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

#### sysadmin-raft-snapshot.sh

This script is run by IT Security personnel who administer the Vault server or via a cron job. It handles:

1. **Automated Raft Snapshots**:
   - Takes a point-in-time snapshot of the Vault Raft storage backend
   - Creates timestamped snapshots for proper tracking
   - Stores snapshots in a configurable location (/opt/vault/snapshots by default)

2. **Retention Management**:
   - Automatically cleans up old snapshots based on retention policy (14 days by default)
   - Prevents snapshot storage from growing indefinitely
   - Logs the number of snapshots being maintained

3. **Robust Logging**:
   - Records all activities in a dedicated log file
   - Captures any errors during the snapshot process
   - Provides an audit trail of backup activities

**Usage**:
- Run manually to create an on-demand snapshot
- Set up with a cron job for regular automated snapshots (recommended)
- Can be customized with different retention periods and storage locations

#### sysadmin-setup-snapshot-cron.sh

This script is run by System Administrators to set up automated snapshot scheduling. It handles:

1. **Script Installation**:
   - Copies the snapshot script to the appropriate system location
   - Sets correct permissions for execution
   - Makes it available for scheduled runs

2. **Cron Configuration**:
   - Creates a dedicated cron job for Vault snapshots
   - Offers flexible scheduling options (hourly, daily, weekly, etc.)
   - Uses proper system cron facilities for reliable scheduling

3. **User Customization**:
   - Allows configuration of the Vault server address
   - Configures which user should run the snapshots
   - Provides sensible defaults that can be overridden

**Usage**:
- Run by System Administrators to set up the snapshot schedule
- Can be re-run to modify the snapshot frequency
- Requires root privileges to create the cron job

#### sysadmin-raft-restore.sh

This script is run by Vault Administrators during disaster recovery scenarios. It handles:

1. **Interactive Restoration**:
   - Displays a list of all available snapshots with timestamps
   - Allows selection of which snapshot to restore
   - Provides clear warnings about the impact of restoration

2. **Safe Recovery Process**:
   - Verifies Vault is running and accessible
   - Checks if the node is the active leader
   - Performs the restore operation in-place without service disruption
   - Tracks Raft Applied Index values for verification

3. **Post-Restoration Verification**:
   - Validates that the Raft Applied Index has changed
   - Confirms Vault remains unsealed after restoration
   - Lists all Raft peers to verify cluster state
   - Provides guidance on next steps after restoration

4. **Comprehensive Logging**:
   - Logs all restoration steps for audit purposes
   - Captures detailed error messages if issues occur
   - Creates a record of which snapshot was restored

**Usage**:
- Run during disaster recovery scenarios
- Requires a Vault token with appropriate permissions
- Interactive process to ensure deliberate restoration choices
- Performs restore without stopping or restarting Vault

#### vault-admin-configure-autopilot.sh

This script is run by Vault Administrators to configure Raft autopilot features. It handles:

1. **Dead Server Cleanup**:
   - Enables automatic cleanup of dead servers in the Raft cluster
   - Configures the timeout threshold for detecting dead servers
   - Sets the minimum quorum value for the cluster
   - Eliminates manual intervention for server turnover in auto-scaling environments

2. **Interactive Configuration**:
   - Provides default values for all settings
   - Allows customization of all autopilot parameters
   - Explains the purpose and impact of each setting

3. **Configuration Verification**:
   - Displays the applied configuration for verification
   - Logs all changes for audit purposes
   - Confirms successful application of settings

**Usage**:
- Run after initial Vault cluster setup
- Critical for environments with server auto-scaling
- Prevents manual Raft configuration management
- Makes cluster more resilient to server failures

#### vault-admin-enable-audit-logs.sh

This script is run by Vault Administrators to enable audit logging. It handles:

1. **Audit Device Setup**:
   - Configures file, syslog, or socket audit devices
   - Creates necessary directories and sets permissions
   - Applies proper formatting and rotation settings
   - Ensures compliance with security requirements

2. **Multiple Device Types**:
   - File audit device for standard logging to disk
   - Syslog audit device for integration with system logs
   - Socket audit device for external log aggregation
   - Customizable settings for each device type

3. **Security Guidance**:
   - Provides warnings about audit device importance
   - Explains the impact of audit device failure
   - Recommends monitoring and storage considerations
   - Educates on best practices for audit log management

**Usage**:
- Run as part of initial Vault configuration
- Essential for security compliance and forensics
- Configure multiple devices for high availability
- Critical for production Vault deployments

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
1. **Self-Managing Vault Agent**:
   - The Vault Agent configuration includes `exit_on_err = true` in the auto_auth section
   - When the Secret ID expires, the Vault Agent process exits with an error
   - The exit happens automatically when authentication can no longer occur

2. **Systemd Integration**:
   - Systemd service is configured with `Restart=on-failure`
   - When the Vault Agent exits due to Secret ID expiry, systemd automatically restarts it
   - The restart triggers the agent's startup script, which:
     - Authenticates using the restart AppRole
     - Obtains a new wrapped Secret ID for the application
     - Starts the Vault Agent with fresh credentials

3. **Event-Driven Approach**:
   - No separate renewal script or scheduled job is needed
   - Renewal is tied to the actual expiration event rather than being time-based
   - This provides more reliable operation and eliminates timing issues

4. **Monitoring and Logging**:
   - All renewal activities are captured in the systemd journal
   - Systemd logs the exit and restart events
   - The Vault Agent logs provide detailed authentication information

### Secret ID TTL Configuration
- The Secret ID TTL is defined in the vault-admin-setup.sh script (default: 24 hours)
- When a Secret ID expires, the agent exits and is automatically restarted
- The TTL only needs to be managed on the Vault server side

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
4. Validate that Vault Agent services are running correctly
5. Share token file paths with application teams

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
10. **Disaster Recovery Ready**: Regular automated Raft snapshots provide a robust backup mechanism for recovery scenarios.

## File Permissions and Security Considerations

- Vault Agent runs as the dedicated `vaultagent` system user
- Applications run as the `springApps` user
- Token files are owned by `vaultagent` with group access for `springApps`
- AppRole credentials are stored with restrictive permissions
- Secret ID renewal happens automatically through systemd restart mechanisms
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
# Check if the agent is properly restarting
sudo systemctl status vault-agent-<application>

# View the agent startup logs
sudo journalctl -u vault-agent-<application> -n 50

# Manually restart the service to force credential refresh
sudo systemctl restart vault-agent-<application>
```

## Support and Maintenance

- **Vault Administration**: 
  - Security team should regularly review and audit policies and AppRoles
  - Monitor Raft snapshot logs to ensure backups are completing successfully
  - Verify snapshot retention policy is appropriate for your recovery needs
- **System Administration**: 
  - Monitor Vault Agent services and ensure they're running properly
  - Check service restart patterns to verify Secret ID renewal is working
  - Ensure systemd is properly configured for automatic restarts
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

## Raft Snapshot Management

Vault's integrated storage (Raft) requires regular snapshots for backup and disaster recovery purposes. This implementation provides a comprehensive snapshot solution:

### Why Snapshots Are Essential
- Protect against data loss in case of catastrophic failures
- Enable point-in-time recovery capabilities
- Support cluster expansion and migration scenarios
- Provide offline data analysis capabilities when needed

### How Snapshots Work
1. **Automatic Scheduling**:
   - The `sysadmin-setup-snapshot-cron.sh` script configures a cron job to run at specified intervals
   - Frequency can be configured based on environment (hourly for production, daily for dev, etc.)
   - The schedule can be adjusted without modifying the snapshot logic

2. **Snapshot Process**:
   - The snapshot script authenticates to Vault using a provided token
   - Uses the `vault operator raft snapshot save` command to create consistent backups
   - Applies proper permissions to the snapshot files for security
   - Creates timestamped files to track exactly when each snapshot was taken

3. **Retention Management**:
   - Automatically manages storage by cleaning up snapshots based on age
   - Default retention period is 14 days (configurable)
   - Prevents snapshot storage from growing indefinitely
   - Logs snapshot counts to help monitor storage usage

4. **Security Considerations**:
   - Requires a Vault token with appropriate permissions
   - Snapshots are secured with restrictive file permissions
   - Logs all activities for audit trail purposes
   - Designed to run as a non-privileged user where possible

### Snapshot Usage

To set up automated snapshots:

1. Run the `sysadmin-setup-snapshot-cron.sh` script as root:
   ```bash
   sudo ./sysadmin-setup-snapshot-cron.sh
   ```

2. Follow the interactive prompts to:
   - Select snapshot frequency
   - Specify which user should run the snapshots
   - Configure the Vault server address

To take a manual snapshot:

```bash
# Using the installed script
sudo /usr/local/bin/sysadmin-raft-snapshot.sh

# Or using the local copy directly
sudo ./sysadmin-raft-snapshot.sh
```

### Best Practices

- Take snapshots more frequently in high-change environments
- Store snapshots in a separate physical location when possible
- Test restoration procedures regularly using snapshots
- Monitor snapshot logs for any failures
- Configure appropriate alerting if snapshots fail

### Snapshot Restoration

In the event of a disaster recovery scenario, you can restore a Vault instance from a snapshot using the provided script:

```bash
# Run the interactive restore script
sudo ./sysadmin-raft-restore.sh
```

The script will:
1. List all available snapshots
2. Allow you to select which one to restore
3. Check if you're on the Vault leader node
4. Record the current Raft Applied Index
5. Restore from the selected snapshot
6. Compare the Raft Applied Index before and after to verify success
7. Confirm that Vault remains unsealed and operational

For manual restoration process:

```bash
# First check the current Raft Applied Index
vault status

# Restore from a snapshot (no need to stop Vault)
vault operator raft snapshot restore /opt/vault/snapshots/vault-raft-snapshot-YYYYMMDD-HHMMSS.snap

# Verify the Raft Applied Index changed
vault status

# Confirm Raft peers are present
vault operator raft list-peers
```

**Important Restoration Notes:**
- Restoring a snapshot replaces the entire Vault data store
- All tokens and leases created after the snapshot was taken will be invalid
- Clients may need to re-authenticate after a restore operation
- In a clustered environment, restore the snapshot on one node (preferably the leader) and let the cluster replicate

## Raft Autopilot Configuration

Vault's integrated storage (Raft) provides an autopilot feature that can automatically manage server membership, particularly useful in auto-scaling environments.

### Why Autopilot is Essential
- Eliminates manual intervention when servers come and go
- Automatically removes dead servers from the cluster
- Prevents cluster degradation due to unavailable nodes
- Essential for environments with dynamic infrastructure

### How Autopilot Works
1. **Dead Server Cleanup**:
   - When enabled, Vault automatically removes servers that have been unreachable
   - Uses a configurable threshold to determine when a server is considered "dead"
   - Maintains the minimum quorum to ensure cluster stability
   - Performs cleanup without manual intervention

2. **Configuration Parameters**:
   - `cleanup-dead-servers`: Enable/disable automatic removal of dead servers
   - `dead-server-last-contact-threshold`: Time in seconds before a server is considered dead
   - `min-quorum`: Minimum number of servers needed for the cluster to function

3. **Implementation**:
   - The `vault-admin-configure-autopilot.sh` script provides an interactive way to set these parameters
   - Settings are applied cluster-wide and persist across restarts
   - Changes take effect immediately without disruption

### Configuring Autopilot

To configure Raft autopilot:

```bash
# Run the interactive configuration script
./vault-admin-configure-autopilot.sh
```

For manual configuration:

```bash
# Enable dead server cleanup
vault operator raft autopilot set-config \
   -cleanup-dead-servers=true \
   -dead-server-last-contact-threshold=10 \
   -min-quorum=3

# Verify current configuration
vault operator raft autopilot get-config
```

### Best Practices
- Always enable dead server cleanup in production environments
- Set the contact threshold based on your network reliability (10 seconds is typical)
- Configure min-quorum to at least (n/2)+1 where n is your total server count
- Verify autopilot configuration after cluster changes

## Audit Logging

Vault audit logging is a critical component for security, compliance, and troubleshooting.

### Why Audit Logging is Critical
- Provides a complete record of all requests and responses
- Essential for security incident investigations
- Often required for compliance (PCI-DSS, HIPAA, etc.)
- Helps troubleshoot authentication and authorization issues

### How Audit Logging Works
1. **Audit Devices**:
   - Vault supports multiple types of audit devices (file, syslog, socket)
   - Each device can be configured independently
   - Multiple devices can be enabled simultaneously for redundancy
   - If all audit devices fail, Vault will seal itself for security

2. **Log Contents**:
   - All requests and responses are logged (with sensitive data hashed)
   - Authentication attempts (successful and failed)
   - Token creation, usage, and revocation
   - Secret access events and policy evaluations

3. **Implementation**:
   - The `vault-admin-enable-audit-logs.sh` script configures audit devices interactively
   - File audit device writes to a specified file path
   - Syslog device integrates with system logging
   - Socket device sends logs to external receivers

### Enabling Audit Logging

To configure audit logging:

```bash
# Run the interactive setup script
./vault-admin-enable-audit-logs.sh
```

For manual configuration:

```bash
# Enable file audit device
vault audit enable file file_path=/var/log/vault/audit.log

# Enable syslog audit device
vault audit enable syslog tag=vault-audit facility=AUTH

# List enabled audit devices
vault audit list
```

### Best Practices
- Enable at least two audit devices for redundancy
- Monitor audit log storage to prevent disk space issues
- Implement log rotation for file-based audit devices
- Set up proper permissions on audit log files
- Consider offloading audit logs to a SIEM system