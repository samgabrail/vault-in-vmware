#!/bin/bash

# Audit Log Analysis Script
AUDIT_LOG="./audit-logs/vault-audit.log"

echo "=== Vault Audit Log Analysis ==="
echo

if [[ ! -f "$AUDIT_LOG" ]]; then
    echo "❌ Audit log not found: $AUDIT_LOG"
    exit 1
fi

echo "📊 Audit Log Statistics:"
echo "   Total events: $(wc -l < $AUDIT_LOG)"
echo "   File size: $(du -h $AUDIT_LOG | cut -f1)"
echo "   Date range: $(head -1 $AUDIT_LOG | jq -r .time) to $(tail -1 $AUDIT_LOG | jq -r .time)"
echo

echo "📋 Event Types:"
jq -r .type $AUDIT_LOG | sort | uniq -c | sort -nr
echo

echo "🔑 Most Accessed Paths:"
jq -r 'select(.request.path != null) | .request.path' $AUDIT_LOG | sort | uniq -c | sort -nr | head -10
echo

echo "👤 Client IPs:"
jq -r 'select(.request.client_ip != null) | .request.client_ip' $AUDIT_LOG | sort | uniq -c | sort -nr
echo

echo "⚠️  Failed Operations:"
jq -r 'select(.error != null) | "\(.time) \(.request.path) \(.error)"' $AUDIT_LOG | head -5
echo

echo "🔄 Secret Rotations (KV puts):"
jq -r 'select(.request.operation == "update" and (.request.path | startswith("static-secrets"))) | "\(.time) \(.request.path)"' $AUDIT_LOG
echo

echo "✅ Audit analysis complete"
