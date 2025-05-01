#!/bin/bash
# DevOps Integration Script
# This script helps DevOps teams:
# 1. Create sample application code for accessing Vault tokens
# 2. Demonstrate proper token usage patterns
# 3. Facilitate onboarding new applications to use Vault
# 4. Communicate token sink paths to application teams

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

APPS_USER="springApps"
TOKEN_SINK_DIR="/home/$APPS_USER/.vault-tokens"

# Check if running as root or with sudo
check_permissions() {
    # If running as root, we're good
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    
    # If running as the APPS_USER, we're good for scripts directory
    if [ "$(id -un)" = "$APPS_USER" ]; then
        return 0
    fi
    
    # Otherwise, we need to check if we can write to the scripts directory
    if [ ! -w "$1" ]; then
        echo -e "${RED}Error: You don't have write permissions to $1${NC}"
        echo "You can either:"
        echo "1. Run this script with sudo"
        echo "2. Run this script as the $APPS_USER user"
        echo "3. Specify a different directory where you have write permissions"
        return 1
    fi
    
    return 0
}

echo -e "${BLUE}=== DevOps Integration Tools ===${NC}"
echo "This script helps DevOps teams integrate applications with Vault."

# Get application information
echo -e "\n${GREEN}Application Information${NC}"
echo "Please enter the application name(s) you're integrating with Vault."
read -p "Application name(s) (space-separated): " APP_NAMES_INPUT
IFS=' ' read -r -a APP_NAMES <<< "$APP_NAMES_INPUT"

if [ ${#APP_NAMES[@]} -eq 0 ]; then
    echo "No applications specified. Using default examples: webapp database"
    APP_NAMES=("webapp" "database")
fi

# Optional - get information about the Vault server
VAULT_ADDR=${VAULT_ADDR:-"http://127.0.0.1:8200"}
read -p "Enter Vault server address [$VAULT_ADDR]: " input
VAULT_ADDR=${input:-$VAULT_ADDR}

# Ask where to save the example files
SCRIPTS_DIR="/home/$APPS_USER/scripts"
read -p "Enter directory to save sample scripts [$SCRIPTS_DIR]: " input
SCRIPTS_DIR=${input:-$SCRIPTS_DIR}

# Check if we can write to the specified directory
if ! check_permissions "$SCRIPTS_DIR"; then
    read -p "Would you like to specify a different directory? (y/n) [y]: " change_dir
    change_dir=${change_dir:-y}
    
    if [[ "$change_dir" =~ ^[Yy] ]]; then
        read -p "Enter a directory where you have write permissions: " SCRIPTS_DIR
        # Make sure the new directory exists
        mkdir -p "$SCRIPTS_DIR" 2>/dev/null
        
        # Check permissions again
        if ! check_permissions "$SCRIPTS_DIR"; then
            echo -e "${RED}Error: Still can't write to $SCRIPTS_DIR.${NC}"
            echo "Suggestion: Run the script with sudo or as the $APPS_USER user."
            exit 1
        fi
    else
        echo -e "${RED}Warning: Proceeding anyway, but you may encounter permission errors.${NC}"
    fi
fi

# Create the directory if it doesn't exist
if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "Creating directory $SCRIPTS_DIR"
    mkdir -p "$SCRIPTS_DIR" 2>/dev/null
    # Check if creation was successful
    if [ ! -d "$SCRIPTS_DIR" ]; then
        echo -e "${RED}Failed to create directory $SCRIPTS_DIR. Please check permissions.${NC}"
        echo "Suggestion: Run the script with sudo or as the $APPS_USER user."
        exit 1
    fi
fi

echo -e "\n${GREEN}Generating sample application scripts...${NC}"

# Create sample scripts for each application
for i in "${!APP_NAMES[@]}"; do
    app_name=${APP_NAMES[$i]}
    token_path="$TOKEN_SINK_DIR/${app_name}-token"
    
    # Create a Python example
    python_script="$SCRIPTS_DIR/${app_name}-script.py"
    # Use a temporary file first
    cat > "/tmp/${app_name}-script.py" << EOF
#!/usr/bin/env python3
"""
Sample script demonstrating how to use Vault tokens for ${app_name}
Created by DevOps team for application integration
"""
import os
import requests
import json
import time

# Token path provided by SysAdmin and communicated by DevOps
TOKEN_PATH = '${token_path}'
# Main Vault server
VAULT_ADDR = '${VAULT_ADDR}'

def get_vault_token():
    """Get the Vault token from the token sink file"""
    # Wait for token to be available (useful during startup)
    attempts = 0
    while not os.path.exists(TOKEN_PATH) and attempts < 30:
        print(f"Waiting for Vault token at {TOKEN_PATH}...")
        time.sleep(1)
        attempts += 1

    if not os.path.exists(TOKEN_PATH):
        raise FileNotFoundError(f"Error: Token file not found at {TOKEN_PATH}")

    # Read the token
    with open(TOKEN_PATH, 'r') as f:
        return f.read().strip()

def get_secret(path, token):
    """Get a secret from Vault using the provided token"""
    # Set up headers with the token
    headers = {
        'X-Vault-Token': token
    }
    
    # Make the request directly to Vault
    response = requests.get(
        f'{VAULT_ADDR}/v1/{path}',
        headers=headers
    )
    
    # Handle the response
    if response.status_code == 200:
        return response.json()
    else:
        print(f"Error retrieving secret: {response.status_code}")
        print(f"Response: {response.text}")
        return None

def main():
    """Main application logic"""
    try:
        # Get the token
        token = get_vault_token()
        print(f"Successfully retrieved Vault token from {TOKEN_PATH}")
        
        # Example: Get application secrets from Vault
        print(f"Retrieving secrets for ${app_name}...")
        
        # Direct Vault access
        secret_path = "secret/data/${app_name}/config"
        secret_data = get_secret(secret_path, token)
        
        if secret_data and 'data' in secret_data:
            data = secret_data['data']['data']
            print(f"API Key: {data.get('api-key')}")
            print(f"DB Password: {data.get('db-password')}")
            
            # Example: Additional secret fields would be accessed here
            # print(f"Other Field: {data.get('other-field')}")
        
    except Exception as e:
        print(f"Error: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    exit(main())
EOF

    # Move the file to the final destination with error handling
    if ! mv "/tmp/${app_name}-script.py" "$python_script" 2>/dev/null; then
        echo -e "${RED}Failed to create $python_script. Check permissions.${NC}"
    else
        # Make the script executable
        chmod 755 "$python_script" 2>/dev/null || echo -e "${RED}Failed to make $python_script executable.${NC}"
    fi
    
    # Create a Java example 
    java_script="$SCRIPTS_DIR/${app_name}-VaultClient.java"
    # Use a temporary file first
    cat > "/tmp/${app_name}-VaultClient.java" << EOF
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Base64;
import org.json.JSONObject;

/**
 * Example Java client for accessing Vault tokens
 * For ${app_name} application
 */
public class ${app_name^}VaultClient {
    // Token path provided by SysAdmin and communicated by DevOps
    private static final String TOKEN_PATH = "${token_path}";
    // Main Vault server
    private static final String VAULT_ADDR = "${VAULT_ADDR}";
    
    private final HttpClient httpClient = HttpClient.newHttpClient();
    private String vaultToken;
    
    public ${app_name^}VaultClient() throws IOException {
        // Read the Vault token
        vaultToken = readVaultToken();
    }
    
    private String readVaultToken() throws IOException {
        // Read the token from the file system
        return Files.readString(Paths.get(TOKEN_PATH)).trim();
    }
    
    public JSONObject getSecret(String path) throws IOException, InterruptedException {
        // Create the HTTP request
        HttpRequest request = HttpRequest.newBuilder()
            .uri(URI.create(VAULT_ADDR + "/v1/" + path))
            .header("X-Vault-Token", vaultToken)
            .build();
        
        // Send the request
        HttpResponse<String> response = httpClient.send(request, 
            HttpResponse.BodyHandlers.ofString());
        
        // Handle the response
        if (response.statusCode() == 200) {
            return new JSONObject(response.body());
        } else {
            System.err.println("Error retrieving secret: " + response.statusCode());
            System.err.println("Response: " + response.body());
            return null;
        }
    }
    
    public static void main(String[] args) {
        try {
            ${app_name^}VaultClient client = new ${app_name^}VaultClient();
            System.out.println("Successfully retrieved Vault token from " + TOKEN_PATH);
            
            // Example: Get application secrets from Vault
            System.out.println("Retrieving secrets for ${app_name}...");
            
            String secretPath = "secret/data/${app_name}/config";
            JSONObject secretData = client.getSecret(secretPath);
            
            if (secretData != null) {
                JSONObject data = secretData.getJSONObject("data").getJSONObject("data");
                System.out.println("API Key: " + data.getString("api-key"));
                System.out.println("DB Password: " + data.getString("db-password"));
                
                // Example: Additional secret fields would be accessed here
                // System.out.println("Other Field: " + data.getString("other-field"));
            }
            
        } catch (Exception e) {
            System.err.println("Error: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
}
EOF

    # Move the file to the final destination with error handling
    if ! mv "/tmp/${app_name}-VaultClient.java" "$java_script" 2>/dev/null; then
        echo -e "${RED}Failed to create $java_script. Check permissions.${NC}"
    fi

    # Create a Node.js example
    node_script="$SCRIPTS_DIR/${app_name}-vault.js"
    # Use a temporary file first
    cat > "/tmp/${app_name}-vault.js" << EOF
#!/usr/bin/env node
/**
 * Example Node.js client for accessing Vault tokens
 * For ${app_name} application
 */
const fs = require('fs');
const path = require('path');
const axios = require('axios');

// Token path provided by SysAdmin and communicated by DevOps
const TOKEN_PATH = '${token_path}';
// Main Vault server
const VAULT_ADDR = '${VAULT_ADDR}';

/**
 * Read the Vault token from the filesystem
 */
async function getVaultToken() {
    return new Promise((resolve, reject) => {
        fs.readFile(TOKEN_PATH, 'utf8', (err, data) => {
            if (err) {
                reject(new Error(\`Error reading Vault token from \${TOKEN_PATH}: \${err.message}\`));
                return;
            }
            resolve(data.trim());
        });
    });
}

/**
 * Get a secret from Vault
 */
async function getSecret(path, token) {
    try {
        const response = await axios.get(\`\${VAULT_ADDR}/v1/\${path}\`, {
            headers: {
                'X-Vault-Token': token
            }
        });
        
        return response.data;
    } catch (error) {
        console.error(\`Error retrieving secret from \${VAULT_ADDR}/\${path}:\`);
        console.error(error.response ? error.response.data : error.message);
        return null;
    }
}

/**
 * Main application logic
 */
async function main() {
    try {
        // Get the token
        const token = await getVaultToken();
        console.log(\`Successfully retrieved Vault token from \${TOKEN_PATH}\`);
        
        // Example: Get application secrets from Vault
        console.log(\`Retrieving secrets for ${app_name}...\`);
        
        // Direct Vault access
        const secretPath = 'secret/data/${app_name}/config';
        const secretData = await getSecret(secretPath, token);
        
        if (secretData && secretData.data) {
            const data = secretData.data.data;
            console.log(\`API Key: \${data['api-key']}\`);
            console.log(\`DB Password: \${data['db-password']}\`);
            
            // Example: Additional secret fields would be accessed here
            // console.log(\`Other Field: \${data['other-field']}\`);
        }
        
    } catch (error) {
        console.error(\`Error: \${error.message}\`);
        process.exit(1);
    }
}

// Run the main function
main();
EOF

    # Move the file to the final destination with error handling
    if ! mv "/tmp/${app_name}-vault.js" "$node_script" 2>/dev/null; then
        echo -e "${RED}Failed to create $node_script. Check permissions.${NC}"
    else
        chmod 755 "$node_script" 2>/dev/null || echo -e "${RED}Failed to make $node_script executable.${NC}"
    fi
    
    echo "Created example scripts for $app_name:"
    echo "- Python: $python_script"
    echo "- Java: $java_script"
    echo "- Node.js: $node_script"
    echo ""
done

echo -e "\n${GREEN}Creating documentation for application teams...${NC}"
# Create documentation for application teams
docs_file="$SCRIPTS_DIR/vault-integration-guide.md"
# Use a temporary file first
cat > "/tmp/vault-integration-guide.md" << EOF
# Vault Integration Guide for Application Teams

This guide explains how to integrate your application with HashiCorp Vault using the token file provided by the Vault Agent.

## Token File Locations

Each application has its own dedicated token file. Your DevOps team will provide you with the specific path for your application:

$(for app_name in "${APP_NAMES[@]}"; do
  echo "- **${app_name}**: \`$TOKEN_SINK_DIR/${app_name}-token\`"
done)

## Integration Steps

1. **Read the token from the file system**
   - The token is stored in a file at the path provided above
   - Your application should read this file to get the Vault token
   - Ensure proper error handling if the file is not accessible

2. **Use the token to authenticate with Vault**
   - Add the token to the \`X-Vault-Token\` header when making requests to Vault
   - All requests should go directly to the Vault server

3. **Implement proper error handling**
   - Handle cases where the token file is not available
   - Handle Vault API errors and connectivity issues
   - Implement retry logic with reasonable backoff

## Best Practices

1. **Token Refresh**: The Vault Agent automatically keeps the token fresh, your application doesn't need to handle token renewal
2. **Secret Rotation**: Your application should handle secret rotation gracefully
3. **Error Handling**: Always include robust error handling for Vault operations
4. **Secure Token Handling**: Never log or expose the Vault token in your application

## Example Code

Example integration code has been provided for several programming languages:

$(for app_name in "${APP_NAMES[@]}"; do
  echo "### ${app_name^} Examples:"
  echo "- Python: \`${app_name}-script.py\`"
  echo "- Java: \`${app_name}-VaultClient.java\`"
  echo "- Node.js: \`${app_name}-vault.js\`"
  echo ""
done)

## Troubleshooting

**Token not available?**
- Check if the Vault Agent is running: \`systemctl status vault-agent-<app-name>\`
- Verify file permissions on the token file
- Ensure your application has read access to the token file
- Contact the System Administrator if the issue persists

**Connection issues?**
- Verify the Vault server is accessible
- Ensure correct network connectivity

## File Permissions

- Token file ownership: \`vaultagent:springApps\` with mode \`440\` (readable by the owner and group)
- Your application should run as the \`springApps\` user to read the token file
- If your application runs as a different user, work with your System Administrator to set up appropriate permissions

## Support

For questions or issues, contact:
- DevOps Team: devops@example.com
- System Administration: sysadmin@example.com
- Security Team: security@example.com

EOF

# Move the file to the final destination with error handling
if ! mv "/tmp/vault-integration-guide.md" "$docs_file" 2>/dev/null; then
    echo -e "${RED}Failed to create $docs_file. Check permissions.${NC}"
else
    echo -e "${GREEN}Created integration guide:${NC} $docs_file"
fi

echo -e "\n${BLUE}==== TOKEN SINK PATHS FOR APPLICATION TEAMS ====${NC}"
echo "It's your responsibility to communicate these token paths to application teams:"
echo ""

for i in "${!APP_NAMES[@]}"; do
    app_name=${APP_NAMES[$i]}
    
    echo -e "${GREEN}${app_name}:${NC}"
    echo "- Token Path: $TOKEN_SINK_DIR/${app_name}-token"
    echo "- Secret Path: secret/data/${app_name}/config"
    echo ""
done

# Check if any token files exist yet
echo -e "\n${BLUE}==== TOKEN FILE STATUS ====${NC}"
found_tokens=false
for app_name in "${APP_NAMES[@]}"; do
    token_path="$TOKEN_SINK_DIR/${app_name}-token"
    if [ -f "$token_path" ]; then
        echo -e "${GREEN}✓${NC} Token for ${app_name} exists"
        # Check permissions if possible
        if [ -r "$token_path" ]; then
            owner=$(stat -c '%U:%G' "$token_path" 2>/dev/null || echo "unknown:unknown")
            perms=$(stat -c '%a' "$token_path" 2>/dev/null || echo "unknown")
            echo "  Owner: $owner, Permissions: $perms"
        else
            echo "  Token exists but permission check failed (may need root access)"
        fi
        found_tokens=true
    else
        echo -e "${RED}✗${NC} Token for ${app_name} does not exist yet"
        echo "  The Vault Agent service for this application may not be running."
        echo "  System administrators should start the service: sudo systemctl start vault-agent-${app_name}"
    fi
done

if [ "$found_tokens" = false ]; then
    echo -e "\n${RED}Warning: No token files found!${NC}"
    echo "This could be because:"
    echo "1. The Vault Agent services haven't been started yet"
    echo "2. The System Administrator hasn't completed setup"
    echo "3. You don't have permission to view the token directory"
fi

echo -e "\n${GREEN}DevOps integration complete!${NC}"
echo "Next steps:"
echo "1. Share the sample scripts with application teams"
echo "2. Distribute the integration guide"
echo "3. IMPORTANT: Communicate token sink paths to application teams"
echo "4. Provide support for teams during integration"
echo "" 

# Final permissions check and suggestions
if [ "$(id -u)" -ne 0 ] && [ "$(id -un)" != "$APPS_USER" ]; then
    echo -e "${BLUE}===== PERMISSIONS NOTE =====${NC}"
    echo "You ran this script as $(id -un), but the token files are owned by $APPS_USER."
    echo "For production use, consider:"
    echo "1. Running this script as the $APPS_USER user"
    echo "2. Running with sudo to ensure all permissions are correctly set"
    echo "3. Copying the generated scripts to a location where application developers can access them"
fi 