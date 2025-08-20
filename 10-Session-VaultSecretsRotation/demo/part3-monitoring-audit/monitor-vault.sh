#!/bin/bash

# Vault Monitoring Script
# This script demonstrates various monitoring queries

echo "=== Vault Monitoring Dashboard ==="
echo

# System health
echo "🏥 System Health:"
vault status | grep -E "(Sealed|Version|HA Mode)"
echo

# Audit devices
echo "📋 Audit Devices:"
vault audit list
echo

# Secrets engines
echo "🔧 Secrets Engines:"
vault secrets list | grep -E "(Path|Type)"
echo

# Recent audit events (last 20 lines)
echo "📜 Recent Audit Events:"
if [[ -f ./audit-logs/vault-audit.log ]]; then
    echo "   Latest 5 audit events:"
    tail -5 ./audit-logs/vault-audit.log | jq -r '"\(.time) \(.type) \(.request.path)"'
else
    echo "   No audit log found"
fi
echo

# Token usage
echo "🎫 Token Information:"
vault token lookup -format=json | jq -r '"TTL: " + .data.ttl + "s, Uses: " + .data.num_uses + ", Policies: " + (.data.policies | join(", "))'
echo

echo "✅ Monitoring snapshot complete"
