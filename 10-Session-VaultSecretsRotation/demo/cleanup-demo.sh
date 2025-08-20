#!/bin/bash

# Complete Demo Cleanup Script
echo "=== Vault Secret Rotation Demo Cleanup ==="
echo

# Stop Vault server
echo "🛑 Stopping Vault server..."
pkill -f "vault server" || echo "   Vault process not found"

# Stop and remove MySQL container
echo "🗄️  Stopping MySQL container..."
if docker ps -q -f name=vault-mysql-demo >/dev/null 2>&1; then
    docker stop vault-mysql-demo >/dev/null 2>&1
    docker rm vault-mysql-demo >/dev/null 2>&1
    echo "   ✅ MySQL container stopped and removed"
else
    echo "   ℹ️  MySQL container not running"
fi

# Clean up temporary files
echo "🧹 Cleaning up temporary files..."
find . -name "*.backup.*" -delete 2>/dev/null
rm -rf part*/mysql-configs/ 2>/dev/null
rm -rf part3-monitoring-audit/audit-logs/ 2>/dev/null

# Remove dynamic users that might still exist
echo "🔧 Cleanup complete!"
echo
echo "📋 What was cleaned up:"
echo "   • Vault development server stopped"
echo "   • MySQL container stopped and removed"
echo "   • Temporary backup files deleted"
echo "   • Audit logs directory removed"
echo
echo "✅ Demo environment fully cleaned up!"
echo "💡 To run the demo again, use: ./master-demo.sh"
