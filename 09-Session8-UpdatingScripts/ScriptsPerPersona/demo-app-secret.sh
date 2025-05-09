#!/bin/bash
##############################################################################
# Demo App Secret Script
#
# PURPOSE:
# This script demonstrates how an application can retrieve secrets from Vault
# using the token created by Vault Agent. It serves as both a testing tool and
# an educational example for developers.
#
# CONTEXT:
# In a Vault Agent workflow, each application has a dedicated token file that 
# is automatically maintained by the Vault Agent. This token can be used by the
# application to authenticate to Vault and retrieve secrets without needing to
# know the AppRole credentials directly.
#
# WORKFLOW:
# 1. Reads a token from a file created by Vault Agent
# 2. Uses this token to authenticate to Vault
# 3. Retrieves a secret from a specified path
# 4. Displays the secret contents
#
# USAGE EXAMPLE:
# ./demo-app-secret.sh webapp
# ./demo-app-secret.sh -p secret/data/webapp/credentials webapp
##############################################################################

# ANSI color codes for better terminal output readability
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
APPS_USER="springapps"
TOKEN_SINK_DIR="/home/$APPS_USER/.vault-tokens"
VAULT_ADDR="http://127.0.0.1:8200"

# ----------------------------------------------------------------------------
# Function to display usage instructions and examples
# ----------------------------------------------------------------------------
usage() {
    echo "Usage: $0 [OPTIONS] APP_NAME"
    echo ""
    echo "Demonstrates retrieving a secret for an application using the token from the token sink file."
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -a, --addr VAULT_ADDR   Specify the Vault server address (default: http://127.0.0.1:8200)"
    echo "  -p, --path SECRET_PATH  Specify the secret path (default: secret/data/APP_NAME/config)"
    echo ""
    echo "Example:"
    echo "  $0 webapp               # Retrieve secrets for webapp using the default path"
    echo "  $0 -p secret/data/webapp/credentials webapp  # Use a custom path"
    exit 1
}

# ----------------------------------------------------------------------------
# Command line argument processing
# ----------------------------------------------------------------------------
# Parse command line options using a while loop and case statement
SECRET_PATH=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -a|--addr)
            # Override the default Vault server address
            VAULT_ADDR="$2"
            shift 2
            ;;
        -p|--path)
            # Override the default secret path
            SECRET_PATH="$2"
            shift 2
            ;;
        *)
            # Any non-option argument is treated as the application name
            APP_NAME="$1"
            shift
            ;;
    esac
done

# Validate that an application name was provided
if [ -z "$APP_NAME" ]; then
    echo -e "${RED}Error: Application name is required${NC}"
    usage
fi

# Set default secret path if not specified
if [ -z "$SECRET_PATH" ]; then
    # By convention, application secrets are stored at secret/data/APP_NAME/config
    SECRET_PATH="secret/data/$APP_NAME/config"
fi

# ----------------------------------------------------------------------------
# Display execution parameters
# ----------------------------------------------------------------------------
echo -e "${BLUE}=== Demo: Accessing Vault Secret with Token ===${NC}"
echo "Application: $APP_NAME"
echo "Secret Path: $SECRET_PATH"
echo "Vault Server: $VAULT_ADDR"

# ----------------------------------------------------------------------------
# Token file verification and reading
# ----------------------------------------------------------------------------
# Each application has its own token file created by the Vault Agent
TOKEN_PATH="$TOKEN_SINK_DIR/${APP_NAME}-token"
if [ ! -f "$TOKEN_PATH" ]; then
    echo -e "${RED}Error: Token file not found at $TOKEN_PATH${NC}"
    echo "Make sure the Vault Agent service for $APP_NAME is running."
    echo "You can start it with: sudo systemctl start vault-agent-${APP_NAME}"
    exit 1
fi

# Verify the token file is readable with proper permissions
echo -e "\n${GREEN}Reading token from $TOKEN_PATH...${NC}"
if [ ! -r "$TOKEN_PATH" ]; then
    echo -e "${RED}Error: Cannot read token file. Permission denied.${NC}"
    echo "Try running this script as root or as the $APPS_USER user."
    exit 1
fi

# Read the token and display a truncated version for security
TOKEN=$(cat "$TOKEN_PATH")
echo "Token: ${TOKEN:0:10}... (truncated for security)"

# ----------------------------------------------------------------------------
# Secret retrieval using the Vault HTTP API with curl
# ----------------------------------------------------------------------------
echo -e "\n${GREEN}Retrieving secret from Vault...${NC}"
# Build the curl command to access the Vault KV API
CURL_CMD="curl -s -H \"X-Vault-Token: $TOKEN\" $VAULT_ADDR/v1/$SECRET_PATH"
echo "Command: curl -s -H \"X-Vault-Token: \$TOKEN\" $VAULT_ADDR/v1/$SECRET_PATH"

# Execute the curl command and capture the response
RESPONSE=$(eval $CURL_CMD)
HTTP_STATUS=$(echo $RESPONSE | grep -o '"http_status_code":[0-9]*' | cut -d':' -f2)

# Handle error responses from Vault
if [[ "$RESPONSE" == *"errors"* ]]; then
    echo -e "${RED}Error retrieving secret:${NC}"
    # Try to format error as JSON if jq is available
    echo $RESPONSE | jq 2>/dev/null || echo $RESPONSE
    exit 1
fi

# ----------------------------------------------------------------------------
# Display the retrieved secret
# ----------------------------------------------------------------------------
echo -e "\n${GREEN}Secret retrieved successfully:${NC}"
# Use jq to format the JSON response if available
echo $RESPONSE | jq '.data.data' 2>/dev/null || echo $RESPONSE

# ----------------------------------------------------------------------------
# Summary and conclusion
# ----------------------------------------------------------------------------
echo -e "\n${BLUE}=== Demo Complete ===${NC}"
echo "This demonstrates that:"
echo "1. The token was successfully created by the Vault Agent"
echo "2. The token has the correct permissions to access the secret"
echo "3. The application can use this token to authenticate to Vault"
echo ""
echo "In a real application, this token would be used similarly to access secrets programmatically." 