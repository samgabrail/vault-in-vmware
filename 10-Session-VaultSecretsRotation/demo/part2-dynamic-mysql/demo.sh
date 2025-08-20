#!/bin/bash

# Part 2: Dynamic MySQL Credentials Demo
# This script demonstrates dynamic credential generation in contrast to Part 1's static rotation

set -e

echo "=== Part 2: Dynamic MySQL Credentials Demo ==="
echo

# Check prerequisites
if ! command -v vault &> /dev/null; then
    echo "❌ Vault CLI not found. Please install Vault."
    exit 1
fi

if ! vault status >/dev/null 2>&1; then
    echo "❌ Vault is not running or not accessible."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ jq not found. Please install jq for JSON processing."
    exit 1
fi

if ! docker ps -q -f name=vault-mysql-demo >/dev/null 2>&1; then
    echo "❌ MySQL container not running. This demo requires the same MySQL from Part 1."
    exit 1
fi

echo "✅ Prerequisites satisfied"
echo

# Show the contrast with Part 1
echo "🔄 Dynamic vs Static Comparison:"
echo "================================="
echo
echo "❌ Part 1 (Static Rotation) Issues:"
echo "   • Long-lived credentials in MySQL"
echo "   • Manual rotation required"
echo "   • Credentials exist even when not in use"
echo
echo "✅ Part 2 (Dynamic Secrets) Benefits:"
echo "   • Credentials created on-demand"
echo "   • Automatic expiration (no rotation needed)"
echo "   • Unique credentials for each request"
echo
read -p "Press Enter to start generating dynamic credentials..."
echo

# Show current MySQL users (should include the static user from Part 1)
echo "📊 Current MySQL Users (Before Dynamic Generation):"
docker exec vault-mysql-demo mysql -u root -prootpassword -e "
SELECT 
    User,
    CASE 
        WHEN User = 'app-service-user' THEN 'Static (from Part 1)'
        WHEN User = 'root' THEN 'System account'
        ELSE 'Dynamic (Vault-generated)'
    END as Account_Type
FROM mysql.user 
WHERE User NOT IN ('mysql.session', 'mysql.sys', 'mysql.infoschema')
ORDER BY Account_Type, User;"
echo

# Generate multiple dynamic credentials to show uniqueness
echo "🔑 Generating Multiple Dynamic Credentials:"
echo "=========================================="
echo

echo "Request #1:"
echo "➤ vault read database/creds/dynamic-app"
CREDS1=$(vault read -format=json database/creds/dynamic-app)
USERNAME1=$(echo $CREDS1 | jq -r '.data.username')
echo "   Generated: $USERNAME1"
echo

echo "Request #2:"
echo "➤ vault read database/creds/dynamic-app" 
CREDS2=$(vault read -format=json database/creds/dynamic-app)
USERNAME2=$(echo $CREDS2 | jq -r '.data.username')
echo "   Generated: $USERNAME2"
echo

echo "Request #3:"
echo "➤ vault read database/creds/dynamic-app"
CREDS3=$(vault read -format=json database/creds/dynamic-app)
USERNAME3=$(echo $CREDS3 | jq -r '.data.username')
echo "   Generated: $USERNAME3"
echo

echo "✅ Each request generates unique credentials!"
echo "   User 1: $USERNAME1"
echo "   User 2: $USERNAME2" 
echo "   User 3: $USERNAME3"
echo

# Show current MySQL users (now with dynamic users)
echo "📊 MySQL Users (After Dynamic Generation):"
docker exec vault-mysql-demo mysql -u root -prootpassword -e "
SELECT 
    User,
    CASE 
        WHEN User = 'app-service-user' THEN 'Static (from Part 1)'
        WHEN User = 'root' THEN 'System account'
        WHEN User LIKE 'v-token-%' THEN 'Dynamic (Vault-generated)'
        ELSE 'Other'
    END as Account_Type
FROM mysql.user 
WHERE User NOT IN ('mysql.session', 'mysql.sys', 'mysql.infoschema')
ORDER BY Account_Type, User;"
echo

# Test one of the dynamic credentials
echo "🔍 Testing Dynamic Credential Connection:"
PASSWORD1=$(echo $CREDS1 | jq -r '.data.password')
if docker exec vault-mysql-demo mysql -u"$USERNAME1" -p"$PASSWORD1" demo -e "
SELECT 
    'Dynamic connection works!' as Status,
    USER() as Connected_As,
    COUNT(*) as Available_Records
FROM users;" 2>/dev/null; then
    echo "   ✅ Dynamic credential connection successful"
else
    echo "   ❌ Connection failed"
fi
echo

# Wait for TTL expiration
echo "⏰ Waiting for TTL Expiration:"
echo "=============================="
echo "   ⏱️  Dynamic credentials expire in 10 seconds, waiting 15 seconds to ensure cleanup..."
echo "   🕐 Current time: $(date)"
echo

# Count down
for i in {15..1}; do
    printf "\r   ⏳ Waiting for expiration... %2d seconds remaining" $i
    sleep 1
done
echo
echo

echo "   🕐 After expiration: $(date)"
echo "   🔍 Checking if dynamic users were automatically removed..."

# Check if users still exist
echo "📊 MySQL Users (After TTL Expiration):"
docker exec vault-mysql-demo mysql -u root -prootpassword -e "
SELECT 
    User,
    CASE 
        WHEN User = 'app-service-user' THEN 'Static (from Part 1)'
        WHEN User = 'root' THEN 'System account'
        WHEN User LIKE 'v-token-%' THEN 'Dynamic (should be gone!)'
        ELSE 'Other'
    END as Account_Type
FROM mysql.user 
WHERE User NOT IN ('mysql.session', 'mysql.sys', 'mysql.infoschema')
ORDER BY Account_Type, User;"
echo

# Test if credentials still work
echo "🔍 Testing Expired Credential:"
if docker exec vault-mysql-demo mysql -u"$USERNAME1" -p"$PASSWORD1" demo -e "SELECT 'Still works' as Status;" >/dev/null 2>&1; then
    echo "   ⚠️  Credential still works (MySQL cleanup may take a moment)"
else
    echo "   ✅ Credential automatically expired and removed"
fi
echo

# Final comparison
echo "🎯 Key Takeaways for Dynamic Secrets:"
echo "===================================="
echo "   ✅ No credential sprawl (automatic cleanup)"
echo "   ✅ Perfect forward secrecy (unique per request)"
echo "   ✅ Limited blast radius (short TTL)"
echo "   ✅ No rotation required (ephemeral by design)"
echo "   ✅ Complete audit trail of credential usage"
echo

echo "✅ Part 2 Demo Complete!"
echo
echo "💡 Dynamic secrets eliminate credential rotation entirely!"
echo "💡 Each request gets unique, short-lived credentials"
echo "💡 Best security posture with minimal operational overhead"
echo
echo "💡 Try: vault read database/creds/dynamic-app (generates new credentials each time)"