#!/bin/bash

# MySQL Container Setup for Static Secret Rotation Demo
# This script starts a MySQL container that will be used for both Part 1 (static) and Part 2 (dynamic)

set -e

echo "=== MySQL Container Setup for Demo ==="
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
sleep 15

# Wait for MySQL to be ready
while ! docker exec vault-mysql-demo mysqladmin ping -h localhost -u root -prootpassword >/dev/null 2>&1; do
    echo "   Waiting for MySQL..."
    sleep 2
done

# Create demo table and data
echo "📊 Creating demo table and data..."
docker exec vault-mysql-demo mysql -u root -prootpassword demo -e "
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    product VARCHAR(100) NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

INSERT INTO users (username, email) VALUES 
('alice', 'alice@example.com'),
('bob', 'bob@example.com'),
('charlie', 'charlie@example.com');

INSERT INTO orders (user_id, product, amount) VALUES
(1, 'Laptop', 999.99),
(2, 'Mouse', 29.99),
(3, 'Keyboard', 79.99),
(1, 'Monitor', 299.99);
"

# Create the initial service account for static rotation demo
echo "👤 Creating initial service account for static rotation..."
docker exec vault-mysql-demo mysql -u root -prootpassword demo -e "
CREATE USER IF NOT EXISTS 'app-service-user'@'%' IDENTIFIED BY 'initial-static-password';
GRANT SELECT, INSERT, UPDATE, DELETE ON demo.* TO 'app-service-user'@'%';
FLUSH PRIVILEGES;
"

# Test the service account
echo "🔍 Testing service account connection..."
docker exec vault-mysql-demo mysql -u app-service-user -pinitial-static-password demo -e "
SELECT 'Service account works!' as Status, COUNT(*) as Total_Users FROM users;
"

echo "✅ MySQL container setup complete!"
echo "📋 Connection details:"
echo "   Host: localhost"
echo "   Port: 3306"
echo "   Database: demo"
echo "   Root password: rootpassword"
echo "   Service user: app-service-user"
echo "   Service password: initial-static-password"
echo
echo "🔍 Test connections:"
echo "   Root: mysql -h localhost -u root -prootpassword demo"
echo "   Service: mysql -h localhost -u app-service-user -pinitial-static-password demo"
echo
echo "📊 Sample queries:"
echo "   SELECT * FROM users;"
echo "   SELECT * FROM orders;"