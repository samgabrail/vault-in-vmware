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
echo "🔄 Comparing Dynamic vs Static (Part 1):"
echo "========================================"
echo
echo "❌ Part 1 (Static Rotation) Issues:"
echo "   • Long-lived credentials in MySQL"
echo "   • Manual rotation required"
echo "   • Same credentials used by multiple applications"
echo "   • Credentials exist even when not in use"
echo "   • Manual cleanup of old passwords"
echo
echo "✅ Part 2 (Dynamic Secrets) Benefits:"
echo "   • Credentials created on-demand"
echo "   • Automatic expiration (no rotation needed)"
echo "   • Unique credentials for each request"
echo "   • No standing credentials when not in use"
echo "   • Automatic cleanup"
echo

# Show current MySQL users (should include the static user from Part 1)
echo "📊 Current MySQL Users Before Dynamic Generation:"
echo "================================================"
docker exec vault-mysql-demo mysql -u root -prootpassword -e "
SELECT 
    User,
    Host,
    CASE 
        WHEN User = 'app-service-user' THEN 'Static (from Part 1)'
        WHEN User = 'root' THEN 'System account'
        ELSE 'Dynamic (Vault-generated)'
    END as Account_Type
FROM mysql.user 
WHERE User NOT IN ('mysql.session', 'mysql.sys', 'mysql.infoschema')
ORDER BY Account_Type, User;"
echo

# Function to display credentials nicely
show_credentials() {
    local role=$1
    local description=$2
    echo "🔑 Generating dynamic credentials for role: $role"
    echo "   Purpose: $description"
    
    # Get credentials from Vault
    CREDS=$(vault read -format=json database/creds/$role)
    
    # Extract values
    USERNAME=$(echo $CREDS | jq -r '.data.username')
    PASSWORD=$(echo $CREDS | jq -r '.data.password')
    LEASE_ID=$(echo $CREDS | jq -r '.lease_id')
    TTL=$(echo $CREDS | jq -r '.lease_duration')
    
    echo "   Generated Username: $USERNAME"
    echo "   Generated Password: ${PASSWORD:0:4}****${PASSWORD: -4}"
    echo "   Lease ID: ${LEASE_ID:0:20}..."
    echo "   TTL: ${TTL}s ($(($TTL/60))m $(($TTL%60))s)"
    echo
    
    # Test database connection
    echo "🔍 Testing database connection with generated credentials..."
    if docker exec vault-mysql-demo mysql -u"$USERNAME" -p"$PASSWORD" demo -e "
    SELECT 
        'Dynamic connection successful!' as Status,
        USER() as Connected_As,
        NOW() as Connection_Time,
        COUNT(*) as Available_Records
    FROM users;" 2>/dev/null; then
        echo "   ✅ Dynamic credential connection successful"
    else
        echo "   ❌ Connection failed"
    fi
    echo
    
    # Return the username for later use
    echo "$USERNAME"
}

# Show current database leases
show_leases() {
    echo "📋 Current Dynamic Database Leases:"
    vault list sys/leases/lookup/database/creds/ 2>/dev/null || echo "   No active leases"
    echo
}

# Start demonstrating dynamic credentials
echo "🚀 Demonstrating Dynamic Credential Generation:"
echo "============================================="
echo

# Generate credentials for different roles
DYNAMIC_APP_USER=$(show_credentials "dynamic-app" "Full CRUD operations (3m TTL)")
READONLY_USER=$(show_credentials "dynamic-readonly" "Read-only access (1m TTL)")
CLEANUP_USER=$(show_credentials "cleanup-service" "Maintenance tasks (30s TTL)")

# Show that each request generates unique credentials
echo "🎲 Uniqueness Test - Multiple Requests to Same Role:"
echo "=================================================="
echo "🔑 First request to dynamic-app:"
FIRST_CREDS=$(vault read -format=json database/creds/dynamic-app)
FIRST_USERNAME=$(echo $FIRST_CREDS | jq -r '.data.username')
echo "   Username: $FIRST_USERNAME"

echo
echo "🔑 Second request to dynamic-app (different credentials):"
SECOND_CREDS=$(vault read -format=json database/creds/dynamic-app)
SECOND_USERNAME=$(echo $SECOND_CREDS | jq -r '.data.username')
echo "   Username: $SECOND_USERNAME"

echo
if [[ "$FIRST_USERNAME" != "$SECOND_USERNAME" ]]; then
    echo "   ✅ Each request generates unique credentials"
else
    echo "   ❌ Credentials should be unique per request"
fi
echo

# Show current MySQL users (now with dynamic users)
echo "📊 MySQL Users After Dynamic Generation:"
echo "========================================"
docker exec vault-mysql-demo mysql -u root -prootpassword -e "
SELECT 
    User,
    Host,
    CASE 
        WHEN User = 'app-service-user' THEN 'Static (from Part 1)'
        WHEN User = 'root' THEN 'System account'
        WHEN User LIKE 'v-token-%' THEN 'Dynamic (Vault-generated)'
        ELSE 'Other'
    END as Account_Type,
    CASE 
        WHEN User LIKE 'v-token-%' THEN 'Will auto-expire'
        WHEN User = 'app-service-user' THEN 'Permanent (needs rotation)'
        ELSE 'System'
    END as Lifecycle
FROM mysql.user 
WHERE User NOT IN ('mysql.session', 'mysql.sys', 'mysql.infoschema')
ORDER BY Account_Type, User;"
echo

# Show active leases
show_leases

# Demonstrate renewal
echo "🔄 Demonstrating Credential Renewal:"
echo "==================================="
RENEWAL_CREDS=$(vault read -format=json database/creds/dynamic-app)
RENEWAL_LEASE=$(echo $RENEWAL_CREDS | jq -r '.lease_id')
RENEWAL_USERNAME=$(echo $RENEWAL_CREDS | jq -r '.data.username')
echo "   Generated user: $RENEWAL_USERNAME"
echo "   Lease ID: ${RENEWAL_LEASE:0:20}..."
echo "   Renewing lease for extended access..."
vault lease renew $RENEWAL_LEASE >/dev/null
echo "   ✅ Lease renewed successfully"
echo "   💡 Applications can renew leases before expiration"
echo

# Show automatic cleanup simulation
echo "⏰ Demonstrating Automatic Cleanup:"
echo "=================================="
echo "   ⏱️  Waiting 35 seconds to show cleanup-service user expiration (30s TTL)..."
echo "   🕐 Current time: $(date)"

# Count down
for i in {35..1}; do
    printf "\r   ⏳ Waiting... %2d seconds remaining" $i
    sleep 1
done
echo

echo "   🕐 After expiration: $(date)"
echo "   🔍 Checking if cleanup-service user was automatically removed..."

# Check if the cleanup user still exists
if docker exec vault-mysql-demo mysql -u root -prootpassword -e "SELECT User FROM mysql.user WHERE User = '$CLEANUP_USER';" | grep -q "$CLEANUP_USER"; then
    echo "   ⚠️  User still exists (MySQL cleanup may take a moment)"
else
    echo "   ✅ User automatically cleaned up after TTL expiration"
fi
echo

# Final comparison
echo "🔄 Final Comparison: Static vs Dynamic:"
echo "======================================"
echo
echo "📊 Static Rotation (Part 1):"
echo "   • User: app-service-user (permanent)"
echo "   • Password: Manually rotated"
echo "   • Lifecycle: Exists until manually deleted"
echo "   • Security: Good (with regular rotation)"
echo
echo "📊 Dynamic Secrets (Part 2):"
echo "   • Users: v-token-* (temporary)"
echo "   • Password: Never needs rotation"
echo "   • Lifecycle: Auto-expires based on TTL"
echo "   • Security: Excellent (automatic cleanup)"
echo

# Show the security benefits
echo "🛡️  Security Benefits of Dynamic Secrets:"
echo "======================================="
echo "   ✅ No credential sprawl (automatic cleanup)"
echo "   ✅ Perfect forward secrecy (unique per request)"
echo "   ✅ Limited blast radius (short TTL)"
echo "   ✅ No rotation required (ephemeral by design)"
echo "   ✅ Granular access control per credential"
echo "   ✅ Complete audit trail of credential usage"
echo

echo "✅ Part 2 Demo Complete!"
echo
echo "🎯 Key Takeaways:"
echo "   • Dynamic secrets eliminate credential rotation entirely"
echo "   • Each application request gets unique, short-lived credentials"
echo "   • Automatic cleanup prevents credential accumulation"
echo "   • Best security posture with minimal operational overhead"
echo "   • Ideal for new applications that can integrate with Vault"
echo
echo "💡 Try: vault read database/creds/dynamic-app (generates new credentials each time)"
echo "💡 Next: Part 3 will demonstrate monitoring and audit capabilities"