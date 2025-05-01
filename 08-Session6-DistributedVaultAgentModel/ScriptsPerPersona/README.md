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

### 3. DevOps Team
Responsible for application integration:
- Providing code examples to application teams
- Communicating token sink paths to application developers
- Documenting the integration approach
- Supporting application teams during implementation
- Ensuring applications follow security best practices

## Implementation Scripts

The implementation is split into three separate scripts, each targeting one of the above personas:

1. **[vault-admin-setup.sh](vault-admin-setup.sh)**: Used by Vault Administrators to configure the Vault server.
2. **[sysadmin-setup.sh](sysadmin-setup.sh)**: Used by System Administrators to set up Vault Agent services on application servers.
3. **[devops-integration.sh](devops-integration.sh)**: Used by DevOps teams to create integration examples for application developers.

## Prerequisites

- Linux environment (Ubuntu/Debian recommended)
- Vault CLI installed
- `jq` for JSON parsing
- Python 3 (for sample scripts)
- Root/sudo access (required for systemd operations)
- A running Vault server

## Workflow for Adding a New Application

### Step 1: Vault Administrator
1. Run the `vault-admin-setup.sh` script
2. Enter the new application name when prompted
3. Create appropriate policies for the application
4. Set up the AppRole for the application
5. Securely share restart AppRole credentials with System Administrators

### Step 2: System Administrator
1. Run the `sysadmin-setup.sh` script on the application server
2. Enter the restart AppRole credentials provided by the Vault Administrator
3. Specify the application name to configure
4. Validate that Vault Agent services are running correctly
5. Share token file paths and relevant information with DevOps

### Step 3: DevOps Team
1. Run the `devops-integration.sh` script
2. Generate example integration code for the application
3. Communicate token sink file paths to application developers
4. Create documentation for application teams
5. Provide guidance on best practices
6. Support application teams during integration

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

## Benefits of This Approach

1. **Complete Isolation**: Each application only has access to its own secrets.
2. **Simplified Authentication**: Applications don't need to handle AppRole authentication logic.
3. **Clear Responsibility Model**: Well-defined roles for different teams.
4. **Scalability**: Easy to add new applications to the system.
5. **Security**: Minimal permissions for each component and secure credential delivery.
6. **Simplified User Management**: Using a single Linux user for all applications reduces complexity while maintaining security through AppRole isolation.
7. **Reduced Attack Surface**: By using token-only mode, we eliminate the need for a local agent API endpoint.

## File Permissions and Security Considerations

- Vault Agent runs as the dedicated `vaultagent` system user
- Applications run as the `springApps` user
- Token files are owned by `vaultagent` with group access for `springApps`
- AppRole credentials are stored with restrictive permissions
- Systemd services run with appropriate privileges

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

## Support and Maintenance

- **Vault Administration**: Security team should regularly review and audit policies and AppRoles
- **System Administration**: Monitor Vault Agent services and ensure they're running properly
- **DevOps**: Keep integration documentation and examples up to date, and ensure all application teams have the correct token paths

## Cleanup Instructions

When you need to remove an application:

1. **Vault Administrator**:
   ```bash
   # Remove the AppRole
   vault delete auth/approle/role/<application>-role
   
   # Remove the policy
   vault policy delete <application>-policy
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

3. **DevOps Team**:
   ```bash
   # Remove the example scripts
   rm /home/springApps/scripts/<application>-*
   
   # Update documentation to remove references to the application
   # Notify application teams that the application has been removed
   ```