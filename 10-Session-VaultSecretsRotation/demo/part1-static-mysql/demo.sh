#!/bin/bash

# Part 1: Static MySQL Secret Rotation Demo
# This script orchestrates the complete static MySQL secret rotation demonstration

set -e

echo "=== Part 1: Static MySQL Secret Rotation Demo ==="
echo

# Check prerequisites
if ! command -v vault &> /dev/null; then
    echo "❌ Vault CLI not found. Please install Vault."
    exit 1
fi

if ! vault status >/dev/null 2>&1; then
    echo "❌ Vault is not running or not accessible."
    echo "   Please start Vault dev server: vault server -dev"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ jq not found. Please install jq for JSON processing."
    exit 1
fi

if ! docker ps -q -f name=vault-mysql-demo >/dev/null 2>&1; then
    echo "❌ MySQL container not running. Starting it now..."
    ./mysql-setup.sh
fi

echo "✅ Prerequisites satisfied"
echo

# Show current state
echo "🔍 Current State (Before Rotation):"
echo "==================================="
echo "   Username: app-service-user"
echo "   Password: initial-static-password (never rotated)"
echo

# Test current connection
echo "🔗 Testing current connection:"
if docker exec vault-mysql-demo mysql -u app-service-user -pinitial-static-password demo -e "
SELECT 'Current password works' as Status, COUNT(*) as Total_Records FROM users;" 2>/dev/null; then
    echo "   ✅ Current static password works"
else
    echo "   ❌ Current connection failed"
fi
echo

# Show password policy
echo "🔒 Vault Password Policy:"
echo "   • mysql-static-policy: 24 chars, database-safe"
echo

echo "🎲 Sample password generation:"
echo "➤ vault read -field=password sys/policies/password/mysql-static-policy/generate"
SAMPLE_PASSWORD=$(vault read -field=password sys/policies/password/mysql-static-policy/generate)
echo "   Generated: ${SAMPLE_PASSWORD:0:6}****${SAMPLE_PASSWORD: -6}"
echo

# Show current Vault state
echo "📚 Current Vault Storage:"
echo "➤ vault kv get static-secrets/mysql/service-accounts/app-service-user"
vault kv get static-secrets/mysql/service-accounts/app-service-user | grep -E "(username|password|rotation_status|created)"
echo

# Wait for user to continue
read -p "Press Enter to perform password rotation..."
echo

# Perform the rotation
echo "🔄 Performing Static MySQL Password Rotation:"
echo "=============================================="
./rotate-mysql-password.sh
echo

# Test the final state
echo "🧪 Final Verification:"
echo "====================="
echo

echo "🔗 Testing with rotated credentials from Vault:"
echo "➤ vault kv get -format=json static-secrets/mysql/service-accounts/app-service-user"
VAULT_CREDS=$(vault kv get -format=json static-secrets/mysql/service-accounts/app-service-user)
VAULT_USERNAME=$(echo $VAULT_CREDS | jq -r '.data.data.username')
VAULT_PASSWORD=$(echo $VAULT_CREDS | jq -r '.data.data.password')

if docker exec vault-mysql-demo mysql -u $VAULT_USERNAME -p$VAULT_PASSWORD demo -e "
SELECT 
    'Rotation successful!' as Status,
    USER() as Connected_As,
    COUNT(*) as Total_Records
FROM users;" 2>/dev/null; then
    echo "   ✅ Application can connect using rotated credentials from Vault"
else
    echo "   ❌ Connection failed with rotated credentials"
fi
echo

# Compare with what's coming in Part 2
echo "🔄 Static vs Dynamic Preview:"
echo "============================="
echo
echo "❌ What we just saw (Static Rotation):"
echo "   • Manual password rotation required"
echo "   • Long-lived credentials exist in MySQL"
echo "   • Still significant security improvement"
echo
echo "✅ Coming in Part 2 (Dynamic Secrets):"
echo "   • Automatic credential generation on-demand"
echo "   • Short-lived credentials (seconds/minutes)"
echo "   • No rotation needed (ephemeral by design)"
echo

echo "✅ Part 1 Demo Complete!"
echo
echo "🎯 Key Takeaways:"
echo "   • Vault generates secure passwords using policies"
echo "   • Manual coordination required between systems"  
echo "   • Good for legacy systems that can't use dynamic secrets"
echo
echo "💡 Next: Part 2 will show dynamic secrets with the same MySQL database"