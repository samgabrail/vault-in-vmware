#!/bin/bash

# Part 1: Static MySQL Secret Rotation Setup
# This script sets up the environment for demonstrating static secret rotation for MySQL database

set -e

echo "=== Part 1: Static MySQL Secret Rotation Setup ==="
echo

# Check if Vault is running
if ! vault status >/dev/null 2>&1; then
    echo "❌ Vault is not running or not accessible. Please start Vault dev server first."
    echo "   Run: vault server -dev"
    exit 1
fi

echo "✅ Vault is accessible"

# Enable KV v2 secrets engine for static secrets
echo "📦 Enabling KV v2 secrets engine..."
vault secrets enable -path=static-secrets kv-v2 2>/dev/null || echo "   (already enabled)"

# Create password policy for MySQL passwords (database-friendly)
echo "🔒 Creating password policy 'mysql-static-policy'..."
vault write sys/policies/password/mysql-static-policy policy=-<<EOF
length=24
rule "charset" {
  charset = "abcdefghijklmnopqrstuvwxyz"
  min-chars = 2
}
rule "charset" {
  charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  min-chars = 2
}
rule "charset" {
  charset = "0123456789"
  min-chars = 2
}
rule "charset" {
  charset = "@#%"
  min-chars = 1
}
EOF

# Create a simulated MySQL service account that will be rotated
echo "🎯 Creating MySQL service account simulation..."
mkdir -p ./mysql-configs

# Create the initial MySQL user configuration
cat > ./mysql-configs/app-service-user.sql <<'EOF'
-- MySQL Service Account Configuration
-- This represents the service account that applications use to connect to MySQL

CREATE USER IF NOT EXISTS 'app-service-user'@'%' IDENTIFIED BY 'initial-static-password';
GRANT SELECT, INSERT, UPDATE, DELETE ON demo.* TO 'app-service-user'@'%';
FLUSH PRIVILEGES;
EOF

# Create application configuration that uses the service account
cat > ./mysql-configs/app-connection.conf <<'EOF'
# Application Database Configuration
# This file represents how applications store database connection info

[database]
host=localhost
port=3306
database=demo
username=app-service-user
password=initial-static-password
max_connections=10
timeout=30
last_password_rotation=never
rotation_policy=monthly
EOF

echo "🗄️ Initial MySQL service account setup complete"
echo "   Username: app-service-user"
echo "   Initial Password: initial-static-password"
echo

# Store initial credential in Vault
echo "🏦 Storing initial credential in Vault..."
vault kv put static-secrets/mysql/service-accounts/app-service-user \
    username="app-service-user" \
    password="initial-static-password" \
    host="localhost" \
    port="3306" \
    database="demo" \
    created="$(date -Iseconds)" \
    created_by="$(whoami)" \
    rotation_status="initial" \
    password_policy="mysql-static-policy"

echo "   ✅ Initial credential stored in Vault"
echo

echo "✅ Part 1 setup complete!"
echo "📋 Static MySQL rotation environment ready:"
echo "   • Password policy: mysql-static-policy (24 chars, DB-safe)"
echo "   • Service account: app-service-user"
echo "   • Vault path: static-secrets/mysql/service-accounts/app-service-user"
echo "🚀 Ready to demonstrate static MySQL secret rotation"