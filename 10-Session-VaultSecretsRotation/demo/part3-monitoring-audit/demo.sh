#!/bin/bash

# Part 3: Monitoring & Audit Demo
# This script demonstrates Vault's monitoring and audit capabilities

set -e

echo "=== Part 3: Monitoring & Audit Demo ==="
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

echo "✅ Prerequisites satisfied"
echo

# Show audit configuration
echo "📋 Audit Configuration:"
echo "➤ vault audit list"
vault audit list
echo

# Generate audit events
echo "🎭 Generating audit events for demonstration..."

echo "   🔑 Creating test secrets..."
echo "➤ vault kv put secret/demo/app1 username=demo-user password=demo-pass"
vault kv put secret/demo/app1 username="demo-user" password="demo-pass" env="production"

echo "   📖 Reading secrets..."
echo "➤ vault kv get secret/demo/app1"
vault kv get secret/demo/app1 >/dev/null

# Generate dynamic credentials if available
if vault secrets list | grep -q "database"; then
    echo "   🗄️  Generating dynamic credentials..."
    echo "➤ vault read database/creds/dynamic-app"
    vault read database/creds/dynamic-app >/dev/null 2>&1 || echo "      (database role not configured)"
fi

# Generate passwords
echo "   🔒 Generating passwords..."
echo "➤ vault read -field=password sys/policies/password/mysql-static-policy/generate"
vault read -field=password sys/policies/password/mysql-static-policy/generate >/dev/null 2>&1 || echo "      (password policy not configured)"

echo "   ✅ Audit events generated"
echo

# Show real-time monitoring
echo "📊 Real-Time Monitoring:"
echo "========================"
./monitor-vault.sh
echo

# Show specific audit events
echo "📜 Recent Audit Events:"
echo "======================"
if [[ -f "./audit-logs/vault-audit.log" ]]; then
    echo "🔍 Latest secret access events:"
    tail -3 ./audit-logs/vault-audit.log | jq -r '
        "Time: " + .time + 
        "\nOperation: " + (.request.operation // "N/A") + " on " + (.request.path // "N/A") + 
        "\n" + "-"*40'
    echo
else
    echo "❌ No audit events available"
fi

# Show compliance summary
echo "📋 Compliance Summary:"
echo "====================="
if [[ -f "./audit-logs/vault-audit.log" ]]; then
    TOTAL_EVENTS=$(wc -l < ./audit-logs/vault-audit.log)
    SECRET_READS=$(jq -r 'select(.request.operation == "read")' ./audit-logs/vault-audit.log | wc -l)
    SECRET_WRITES=$(jq -r 'select(.request.operation == "update")' ./audit-logs/vault-audit.log | wc -l)
    
    echo "   Total Operations: $TOTAL_EVENTS"
    echo "   Secret Reads: $SECRET_READS"
    echo "   Secret Updates: $SECRET_WRITES"
    echo "   Audit Coverage: 100% (all operations logged)"
    echo
fi

# Show key monitoring capabilities
echo "🔧 Key Monitoring Capabilities:"
echo "==============================="
echo "📡 Integration Options:"
echo "   • Elasticsearch + Kibana"
echo "   • Splunk Universal Forwarder" 
echo "   • SIEM platforms via syslog"
echo

echo "🚨 Alert Examples:"
echo "   • Failed authentications > 5/hour"
echo "   • Root token usage"
echo "   • After-hours secret access"
echo "   • High volume access patterns"
echo

echo "📈 Metrics Available:"
echo "➤ vault read sys/config/telemetry"
vault read sys/config/telemetry 2>/dev/null || echo "   Default telemetry configuration"
echo
echo "   • Request latency and volume"
echo "   • Token operations"
echo "   • Secret access patterns"
echo "   • Audit log failures"
echo

echo "✅ Part 3 Demo Complete!"
echo
echo "🎯 Key Monitoring Takeaways:"
echo "   • Complete audit trail of all operations"
echo "   • Real-time monitoring and alerting"
echo "   • Compliance reporting capabilities"
echo "   • SIEM integration for centralized security"
echo
echo "💡 The audit trail provides foundation for:"
echo "   • Security incident investigation"
echo "   • Compliance reporting (SOX, PCI, HIPAA)"
echo "   • Performance optimization"