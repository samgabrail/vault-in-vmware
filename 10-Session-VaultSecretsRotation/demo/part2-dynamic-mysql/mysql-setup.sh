#!/bin/bash

# MySQL Container Setup for Dynamic Secrets Demo
# This script starts a MySQL container for the demo

set -e

echo "=== MySQL Container Setup ==="
echo

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Stop existing container if running
if docker ps -q -f name=vault-mysql-demo >/dev/null 2>&1; then
    echo "🛑 Stopping existing MySQL container..."
    docker stop vault-mysql-demo >/dev/null
fi

# Remove existing container if exists
if docker ps -aq -f name=vault-mysql-demo >/dev/null 2>&1; then
    echo "🗑️  Removing existing MySQL container..."
    docker rm vault-mysql-demo >/dev/null
fi

# Start MySQL container
echo "🚀 Starting MySQL container for demo..."
docker run -d \
    --name vault-mysql-demo \
    -e MYSQL_ROOT_PASSWORD=rootpassword \
    -e MYSQL_DATABASE=demo \
    -p 3306:3306 \
    mysql:8.0

echo "⏱️  Waiting for MySQL to be ready..."
sleep 10

# Wait for MySQL to be ready
while ! docker exec vault-mysql-demo mysqladmin ping -h localhost -u root -prootpassword >/dev/null 2>&1; do
    echo "   Waiting for MySQL..."
    sleep 2
done

# Create demo table
echo "📊 Creating demo table and data..."
docker exec vault-mysql-demo mysql -u root -prootpassword demo -e "
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (username, email) VALUES 
('alice', 'alice@example.com'),
('bob', 'bob@example.com'),
('charlie', 'charlie@example.com');
"

echo "✅ MySQL container setup complete!"
echo "📋 Connection details:"
echo "   Host: localhost"
echo "   Port: 3306"
echo "   Database: demo"
echo "   Root password: rootpassword"
echo
echo "🔍 Test connection:"
echo "   mysql -h localhost -u root -prootpassword demo -e 'SELECT * FROM users;'"