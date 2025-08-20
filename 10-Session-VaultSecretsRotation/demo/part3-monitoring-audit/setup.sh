#!/bin/bash

# Part 3: Monitoring & Audit Demo Setup
# This script sets up audit logging and monitoring for the demo

set -e

echo "=== Part 3: Monitoring & Audit Setup ==="
echo

# Check if Vault is running
if ! vault status >/dev/null 2>&1; then
    echo "❌ Vault is not running or not accessible. Please start Vault dev server first."
    echo "   Run: vault server -dev"
    exit 1
fi

echo "✅ Vault is accessible"

# Create audit log directory
echo "📁 Creating audit log directory..."
mkdir -p ./audit-logs

# Enable file audit backend
echo "📋 Enabling file audit backend..."
vault audit enable file file_path=./audit-logs/vault-audit.log 2>/dev/null || echo "   (already enabled)"

# Enable syslog audit backend (if available)
echo "📋 Attempting to enable syslog audit backend..."
vault audit enable syslog 2>/dev/null || echo "   (syslog not available in dev mode)"

# Create some sample audit events
echo "🎭 Generating sample audit events..."

# Some secret operations to create audit trail
vault kv put secret/sample-app \
    username="testuser" \
    password="testpass123" \
    environment="demo"

vault kv get secret/sample-app >/dev/null

vault kv delete secret/sample-app

# Generate some dynamic credentials for audit
if vault secrets list | grep -q "database"; then
    echo "🔑 Generating dynamic credentials for audit trail..."
    vault read database/creds/web-app >/dev/null 2>&1 || echo "   (database role not available)"
fi

# Create monitoring script
echo "📊 Creating monitoring utilities..."

cat > ./monitor-vault.sh <<'EOF'
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
EOF

chmod +x ./monitor-vault.sh

# Create log analysis script
cat > ./analyze-audit.sh <<'EOF'
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
EOF

chmod +x ./analyze-audit.sh

# Create alerting simulation script
cat > ./simulate-alerts.sh <<'EOF'
#!/bin/bash

# Alert Simulation Script
AUDIT_LOG="./audit-logs/vault-audit.log"

echo "=== Vault Alerting Simulation ==="
echo

if [[ ! -f "$AUDIT_LOG" ]]; then
    echo "❌ Audit log not found: $AUDIT_LOG"
    exit 1
fi

# Simulate various alert conditions
echo "🚨 Checking for Alert Conditions..."
echo

# Check for failed authentications
FAILED_AUTH=$(jq -r 'select(.type == "response" and .error != null and (.request.path | startswith("auth")))' $AUDIT_LOG | wc -l)
if [[ $FAILED_AUTH -gt 0 ]]; then
    echo "   ⚠️  ALERT: $FAILED_AUTH failed authentication attempts"
else
    echo "   ✅ No failed authentication attempts"
fi

# Check for root token usage
ROOT_USAGE=$(jq -r 'select(.auth.display_name == "root")' $AUDIT_LOG | wc -l)
if [[ $ROOT_USAGE -gt 0 ]]; then
    echo "   ⚠️  ALERT: Root token used $ROOT_USAGE times"
else
    echo "   ✅ No root token usage detected"
fi

# Check for unusual access patterns (more than 10 requests per minute)
echo "   📊 Access rate analysis:"
jq -r '.time' $AUDIT_LOG | sed 's/\.[0-9]*Z//' | uniq -c | awk '$1 > 10 {print "      ⚠️  HIGH VOLUME: " $1 " requests at " $2}' || echo "      ✅ Normal access patterns"

# Check for secret access outside business hours
echo "   🕐 Business hours compliance:"
AFTER_HOURS=$(jq -r 'select(.time | fromdateiso8601 | strftime("%H") | tonumber > 18 or tonumber < 8) | .time' $AUDIT_LOG | wc -l)
if [[ $AFTER_HOURS -gt 0 ]]; then
    echo "      ⚠️  $AFTER_HOURS secret access events outside business hours"
else
    echo "      ✅ All access within business hours"
fi

echo
echo "🔔 Alert Configuration Examples:"
echo "   • Failed auth > 5/hour → Notify SOC"
echo "   • Root token usage → Immediate alert"
echo "   • High volume access → Rate limiting"
echo "   • After-hours access → Management notification"
echo "   • Secret rotation failures → Operations team"
echo

echo "✅ Alert simulation complete"
EOF

chmod +x ./simulate-alerts.sh

echo
echo "✅ Part 3 setup complete!"
echo "📋 Monitoring tools created:"
echo "   • ./monitor-vault.sh - Real-time monitoring dashboard"
echo "   • ./analyze-audit.sh - Audit log analysis"
echo "   • ./simulate-alerts.sh - Alert condition simulation"
echo "📂 Audit logs will be written to: ./audit-logs/"
echo "🚀 Ready to demonstrate monitoring and audit capabilities"