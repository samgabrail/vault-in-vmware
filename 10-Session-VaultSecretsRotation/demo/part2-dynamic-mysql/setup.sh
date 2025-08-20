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
    allowed_roles="dynamic-app" \
    username="root" \
    password="rootpassword"

# Create a dynamic role for application (10s TTL for quick demo)
echo "👤 Creating dynamic role 'dynamic-app'..."
vault write database/roles/dynamic-app \
    db_name=mysql-demo \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT, INSERT, UPDATE, DELETE ON demo.* TO '{{name}}'@'%';" \
    default_ttl="10s" \
    max_ttl="30s"

echo
echo "✅ Part 2 setup complete!"
echo "📋 Available dynamic role:"
echo "   • dynamic-app (10s TTL) - Full CRUD operations"
echo "🚀 Ready to demonstrate dynamic credential generation"