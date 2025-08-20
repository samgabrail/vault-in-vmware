#!/bin/bash

# Part 2: Dynamic MySQL Credentials Demo Setup
# This script sets up the environment for demonstrating dynamic MySQL credentials

set -e

echo "=== Part 2: Dynamic MySQL Credentials Demo Setup ==="
echo

# Check if Vault is running
if ! vault status >/dev/null 2>&1; then
    echo "❌ Vault is not running or not accessible. Please start Vault dev server first."
    echo "   Run: vault server -dev"
    exit 1
fi

echo "✅ Vault is accessible"

# Check if MySQL container is running (should be from Part 1)
if ! docker ps -q -f name=vault-mysql-demo >/dev/null 2>&1; then
    echo "❌ MySQL container not running. This demo requires the same MySQL from Part 1."
    echo "   Please run Part 1 first or start MySQL container manually."
    exit 1
fi

echo "✅ MySQL container is running (from Part 1)"

# Enable the database secrets engine
echo "📦 Enabling database secrets engine..."
vault secrets enable -path=database database 2>/dev/null || echo "   (already enabled)"

# Configure MySQL connection (uses same container as Part 1)
echo "🔗 Configuring MySQL database connection..."
vault write database/config/mysql-demo \
    plugin_name=mysql-database-plugin \
    connection_url="{{username}}:{{password}}@tcp(localhost:3306)/" \
    allowed_roles="dynamic-app,dynamic-readonly,cleanup-service" \
    username="root" \
    password="rootpassword"

# Create a dynamic role for application (similar permissions as static user)
echo "👤 Creating dynamic role 'dynamic-app'..."
vault write database/roles/dynamic-app \
    db_name=mysql-demo \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT, INSERT, UPDATE, DELETE ON demo.* TO '{{name}}'@'%';" \
    default_ttl="3m" \
    max_ttl="15m"

# Create a read-only role with very short TTL
echo "👤 Creating dynamic role 'dynamic-readonly'..."
vault write database/roles/dynamic-readonly \
    db_name=mysql-demo \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT ON demo.* TO '{{name}}'@'%';" \
    default_ttl="1m" \
    max_ttl="5m"

# Create a cleanup service role for maintenance tasks
echo "👤 Creating dynamic role 'cleanup-service'..."
vault write database/roles/cleanup-service \
    db_name=mysql-demo \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT, DELETE ON demo.* TO '{{name}}'@'%';" \
    default_ttl="30s" \
    max_ttl="2m"

echo
echo "✅ Part 2 setup complete!"
echo "📋 Available dynamic roles:"
echo "   • dynamic-app (3m TTL) - Full CRUD operations"
echo "   • dynamic-readonly (1m TTL) - Read-only access"
echo "   • cleanup-service (30s TTL) - Select and delete only"
echo "🚀 Ready to demonstrate dynamic credential generation"
echo
echo "🔄 Key Difference from Part 1:"
echo "   • No static service accounts in MySQL"
echo "   • Users created on-demand with unique names"
echo "   • Automatic cleanup when TTL expires"
echo "   • Each request gets different credentials"