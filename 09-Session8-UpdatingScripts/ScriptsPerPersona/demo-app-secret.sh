#!/bin/bash
# demo-app-secret.sh
# This script demonstrates how to use the token created by Vault Agent
# to retrieve secrets for an application using curl

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

APPS_USER="springapps"
TOKEN_SINK_DIR="/home/$APPS_USER/.vault-tokens"
VAULT_ADDR="http://127.0.0.1:8200"

# Function to show usage instructions
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

# Parse command line options
SECRET_PATH=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -a|--addr)
            VAULT_ADDR="$2"
            shift 2
            ;;
        -p|--path)
            SECRET_PATH="$2"
            shift 2
            ;;
        *)
            APP_NAME="$1"
            shift
            ;;
    esac
done

# Check if app name was provided
if [ -z "$APP_NAME" ]; then
    echo -e "${RED}Error: Application name is required${NC}"
    usage
fi

# Set default secret path if not specified
if [ -z "$SECRET_PATH" ]; then
    SECRET_PATH="secret/data/$APP_NAME/config"
fi

echo -e "${BLUE}=== Demo: Accessing Vault Secret with Token ===${NC}"
echo "Application: $APP_NAME"
echo "Secret Path: $SECRET_PATH"
echo "Vault Server: $VAULT_ADDR"

# Check if token file exists
TOKEN_PATH="$TOKEN_SINK_DIR/${APP_NAME}-token"
if [ ! -f "$TOKEN_PATH" ]; then
    echo -e "${RED}Error: Token file not found at $TOKEN_PATH${NC}"
    echo "Make sure the Vault Agent service for $APP_NAME is running."
    echo "You can start it with: sudo systemctl start vault-agent-${APP_NAME}"
    exit 1
fi

# Read token from file
echo -e "\n${GREEN}Reading token from $TOKEN_PATH...${NC}"
if [ ! -r "$TOKEN_PATH" ]; then
    echo -e "${RED}Error: Cannot read token file. Permission denied.${NC}"
    echo "Try running this script as root or as the $APPS_USER user."
    exit 1
fi

TOKEN=$(cat "$TOKEN_PATH")
echo "Token: ${TOKEN:0:10}... (truncated for security)"

# Use curl to retrieve the secret
echo -e "\n${GREEN}Retrieving secret from Vault...${NC}"
CURL_CMD="curl -s -H \"X-Vault-Token: $TOKEN\" $VAULT_ADDR/v1/$SECRET_PATH"
echo "Command: curl -s -H \"X-Vault-Token: \$TOKEN\" $VAULT_ADDR/v1/$SECRET_PATH"

RESPONSE=$(eval $CURL_CMD)
HTTP_STATUS=$(echo $RESPONSE | grep -o '"http_status_code":[0-9]*' | cut -d':' -f2)

if [[ "$RESPONSE" == *"errors"* ]]; then
    echo -e "${RED}Error retrieving secret:${NC}"
    echo $RESPONSE | jq 2>/dev/null || echo $RESPONSE
    exit 1
fi

echo -e "\n${GREEN}Secret retrieved successfully:${NC}"
echo $RESPONSE | jq '.data.data' 2>/dev/null || echo $RESPONSE

echo -e "\n${BLUE}=== Demo Complete ===${NC}"
echo "This demonstrates that:"
echo "1. The token was successfully created by the Vault Agent"
echo "2. The token has the correct permissions to access the secret"
echo "3. The application can use this token to authenticate to Vault"
echo ""
echo "In a real application, this token would be used similarly to access secrets programmatically." 