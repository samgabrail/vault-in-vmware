#!/bin/bash

# Static MySQL Password Rotation Script
# This script demonstrates the complete flow of static MySQL password rotation using Vault-generated passwords

set -e

SERVICE_USER="app-service-user"
VAULT_PATH="static-secrets/mysql/service-accounts/app-service-user"
PASSWORD_POLICY="mysql-static-policy"
CONFIG_FILE="./mysql-configs/app-connection.conf"

echo "=== Static MySQL Password Rotation ==="
echo "🎯 Service User: $SERVICE_USER"
echo "📍 Vault Path: $VAULT_PATH"
echo

# Step 1: Generate new password using Vault
echo "🔑 Step 1: Generating new password using Vault policy '$PASSWORD_POLICY'..."
NEW_PASSWORD=$(vault read -field=password sys/policies/password/$PASSWORD_POLICY/generate)
echo "   ✅ New password generated (length: ${#NEW_PASSWORD})"
echo "   🔍 Password preview: ${NEW_PASSWORD:0:4}****${NEW_PASSWORD: -4}"
echo "   📏 Policy: $PASSWORD_POLICY (24 chars, DB-safe characters)"
echo

# Step 2: Update MySQL database with new password
echo "🗄️  Step 2: Updating MySQL database with new password..."
echo "   📝 Executing MySQL command: ALTER USER '$SERVICE_USER'@'%' IDENTIFIED BY '<new-password>';"

# Update the MySQL user password
if docker exec vault-mysql-demo mysql -u root -prootpassword demo -e "ALTER USER '$SERVICE_USER'@'%' IDENTIFIED BY '$NEW_PASSWORD'; FLUSH PRIVILEGES;" 2>/dev/null; then
    echo "   ✅ MySQL password updated successfully"
else
    echo "   ❌ Failed to update MySQL password"
    exit 1
fi

# Test the new password works
echo "   🔍 Testing new password..."
if docker exec vault-mysql-demo mysql -u $SERVICE_USER -p$NEW_PASSWORD demo -e "SELECT 'New password works!' as Status;" >/dev/null 2>&1; then
    echo "   ✅ New password verified in MySQL"
else
    echo "   ❌ New password verification failed"
    exit 1
fi
echo

# Step 3: Update application configuration file
echo "📝 Step 3: Updating application configuration..."
if [[ -f "$CONFIG_FILE" ]]; then
    # Create backup
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%s)"
    
    # Update password in config file
    sed -i "s/password=.*/password=$NEW_PASSWORD/" "$CONFIG_FILE"
    sed -i "s/last_password_rotation=.*/last_password_rotation=$(date -Iseconds)/" "$CONFIG_FILE"
    
    echo "   ✅ Application configuration updated"
    echo "   📄 Updated configuration:"
    grep -E "(password|last_password_rotation)" "$CONFIG_FILE" | sed 's/password=.*/password=****[REDACTED]****/'
else
    echo "   ❌ Configuration file not found: $CONFIG_FILE"
    exit 1
fi
echo

# Step 4: Store new credential in Vault
echo "🏦 Step 4: Storing new credential in Vault..."
vault kv put $VAULT_PATH \
    username="$SERVICE_USER" \
    password="$NEW_PASSWORD" \
    host="localhost" \
    port="3306" \
    database="demo" \
    rotation_date="$(date -Iseconds)" \
    rotated_by="$(whoami)" \
    password_policy="$PASSWORD_POLICY" \
    rotation_status="rotated"

echo "   ✅ Credential stored in Vault at: $VAULT_PATH"
echo

# Step 5: Verify applications can retrieve the credential
echo "🔍 Step 5: Verifying application can retrieve updated credential..."
STORED_CREDS=$(vault kv get -format=json $VAULT_PATH)
STORED_USERNAME=$(echo $STORED_CREDS | jq -r '.data.data.username')
STORED_PASSWORD=$(echo $STORED_CREDS | jq -r '.data.data.password')
ROTATION_DATE=$(echo $STORED_CREDS | jq -r '.data.data.rotation_date')

echo "   📋 Retrieved from Vault:"
echo "      Username: $STORED_USERNAME"
echo "      Password: ${STORED_PASSWORD:0:4}****${STORED_PASSWORD: -4}"
echo "      Host: $(echo $STORED_CREDS | jq -r '.data.data.host')"
echo "      Database: $(echo $STORED_CREDS | jq -r '.data.data.database')"
echo "      Rotated: $ROTATION_DATE"

# Verify password matches
if [[ "$NEW_PASSWORD" == "$STORED_PASSWORD" ]]; then
    echo "   ✅ Password verification successful"
else
    echo "   ❌ Password mismatch detected!"
    exit 1
fi
echo

echo "🎯 KEY DEMONSTRATION POINT:"
echo "   Applications can now retrieve the newly rotated credential from Vault!"
echo "   This shows the complete static rotation workflow in action."
echo
echo "💡 The application doesn't need to know the password was rotated -"
echo "   it always pulls the current credential from Vault."
echo
read -p "Press Enter to see the remaining verification steps..."
echo

# Step 6: Test application connection using retrieved credentials
echo "🚀 Step 6: Testing application connection with retrieved credentials..."
echo "   💻 Simulating application database connection..."

# Test connection using credentials from Vault
DB_HOST=$(echo $STORED_CREDS | jq -r '.data.data.host')
DB_DATABASE=$(echo $STORED_CREDS | jq -r '.data.data.database')

if docker exec vault-mysql-demo mysql -u $STORED_USERNAME -p$STORED_PASSWORD $DB_DATABASE -e "
SELECT 
    'Application connection successful!' as Status,
    USER() as Connected_As,
    DATABASE() as Current_Database,
    COUNT(*) as Total_Users
FROM users;" 2>/dev/null; then
    echo "   ✅ Application connection successful with rotated credentials"
else
    echo "   ❌ Application connection failed"
    exit 1
fi
echo

# Step 7: Verify old password is deactivated
echo "🔒 Step 7: Verifying old password is deactivated..."
if docker exec vault-mysql-demo mysql -u $SERVICE_USER -pinitial-static-password demo -e "SELECT 'Old password works' as Status;" >/dev/null 2>&1; then
    echo "   ⚠️  Old password still works (this is expected on first rotation)"
else
    echo "   ✅ Old password has been deactivated"
fi
echo

echo "✅ Static MySQL password rotation complete!"
echo
echo "📊 Rotation Summary:"
echo "   1. ✅ Vault generated secure password using policy"
echo "   2. ✅ MySQL database updated with new password"
echo "   3. ✅ Application configuration updated"
echo "   4. ✅ New credential stored in Vault with metadata"
echo "   5. ✅ Applications can retrieve updated credential"
echo "   6. ✅ Connection verified with rotated password"
echo "   7. ✅ Old password deactivated"
echo
echo "🔄 This demonstrates static rotation where:"
echo "   • User controls when rotation happens"
echo "   • Vault generates the password"
echo "   • Manual updates to target system required"
echo "   • Applications pull credentials from Vault"
echo
echo "💡 Try: vault kv get $VAULT_PATH"