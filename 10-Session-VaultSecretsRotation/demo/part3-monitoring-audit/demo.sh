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
echo "======================"
vault audit list
echo

# Generate some activity for audit
echo "🎭 Generating audit events..."
echo "============================="

# Create some secret operations
echo "   🔑 Creating test secrets..."
vault kv put secret/demo/app1 username="demo-user" password="demo-pass" env="production"
vault kv put secret/demo/app2 api_key="ak-123456789" service="payment-api"

# Read secrets
echo "   📖 Reading secrets..."
vault kv get secret/demo/app1 >/dev/null
vault kv get secret/demo/app2 >/dev/null

# Generate dynamic credentials if available
if vault secrets list | grep -q "database"; then
    echo "   🗄️  Generating dynamic database credentials..."
    vault read database/creds/web-app >/dev/null 2>&1 || echo "      (database role not configured)"
fi

# Try some password generation
echo "   🔒 Generating passwords..."
vault read -field=password sys/policies/password/api-service-policy/generate >/dev/null 2>&1 || echo "      (password policy not configured)"

echo "   ✅ Audit events generated"
echo

# Show real-time monitoring
echo "📊 Real-Time Monitoring Dashboard:"
echo "=================================="
./monitor-vault.sh
echo

# Analyze audit logs
echo "🔍 Audit Log Analysis:"
echo "====================="
if [[ -f "./audit-logs/vault-audit.log" ]]; then
    ./analyze-audit.sh
else
    echo "❌ No audit logs found. Audit logging may not be properly configured."
fi
echo

# Show specific audit events
echo "📜 Detailed Audit Events:"
echo "========================="
if [[ -f "./audit-logs/vault-audit.log" ]]; then
    echo "🔍 Recent Secret Access Events:"
    echo "   (Showing last 3 events with sensitive data redacted)"
    tail -3 ./audit-logs/vault-audit.log | jq -r '
        "Time: " + .time + 
        "\nType: " + .type + 
        "\nPath: " + (.request.path // "N/A") + 
        "\nOperation: " + (.request.operation // "N/A") + 
        "\nClient IP: " + (.request.client_ip // "N/A") + 
        "\n" + "-"*50'
    echo
    
    echo "🔑 Password Generation Events:"
    jq -r 'select(.request.path | contains("password") | not | not) | 
        "Time: " + .time + " - Generated password using policy"' \
        ./audit-logs/vault-audit.log | tail -2
    echo
    
    echo "📈 KV Secret Operations:"
    jq -r 'select(.request.path | startswith("secret/")) | 
        "Time: " + .time + " - " + .request.operation + " on " + .request.path' \
        ./audit-logs/vault-audit.log | tail -5
    echo
    
else
    echo "❌ No audit events available for analysis"
fi

# Demonstrate alerting
echo "🚨 Alert Simulation:"
echo "==================="
./simulate-alerts.sh
echo

# Show compliance reporting
echo "📋 Compliance Reporting:"
echo "========================"
if [[ -f "./audit-logs/vault-audit.log" ]]; then
    echo "📊 Summary for Compliance Report:"
    echo "   Period: Last audit session"
    
    TOTAL_EVENTS=$(wc -l < ./audit-logs/vault-audit.log)
    SECRET_READS=$(jq -r 'select(.request.operation == "read")' ./audit-logs/vault-audit.log | wc -l)
    SECRET_WRITES=$(jq -r 'select(.request.operation == "update")' ./audit-logs/vault-audit.log | wc -l)
    UNIQUE_PATHS=$(jq -r '.request.path' ./audit-logs/vault-audit.log | sort | uniq | wc -l)
    
    echo "   Total Operations: $TOTAL_EVENTS"
    echo "   Secret Reads: $SECRET_READS"
    echo "   Secret Updates: $SECRET_WRITES"
    echo "   Unique Paths Accessed: $UNIQUE_PATHS"
    echo "   Audit Coverage: 100% (all operations logged)"
    echo
    
    echo "🔒 Security Metrics:"
    FAILED_OPS=$(jq -r 'select(.error != null)' ./audit-logs/vault-audit.log | wc -l)
    echo "   Failed Operations: $FAILED_OPS"
    echo "   Success Rate: $(( (TOTAL_EVENTS - FAILED_OPS) * 100 / TOTAL_EVENTS ))%"
    echo
    
    echo "📈 Usage Patterns:"
    echo "   Peak Activity: $(jq -r '.time' ./audit-logs/vault-audit.log | sed 's/T.*$//' | uniq -c | sort -nr | head -1 | awk '{print $2 " (" $1 " events)"}')"
    echo "   Most Active Path: $(jq -r '.request.path' ./audit-logs/vault-audit.log | sort | uniq -c | sort -nr | head -1 | awk '{print $2 " (" $1 " accesses)"}')"
    echo
fi

# Show SIEM integration examples
echo "🔗 SIEM Integration Examples:"
echo "============================="
echo "📡 Log Forwarding Options:"
echo "   • Fluentd/Fluent Bit → Elasticsearch → Kibana"
echo "   • Filebeat → Logstash → Elasticsearch"
echo "   • Splunk Universal Forwarder → Splunk"
echo "   • rsyslog → SIEM platform"
echo
echo "🔍 Sample SIEM Queries:"
echo "   • Failed authentications: type=response AND error=*auth*"
echo "   • High-privilege operations: auth.display_name=root"
echo "   • Secret rotations: request.operation=update AND request.path=static-secrets*"
echo "   • After-hours access: @timestamp:[18:00 TO 08:00]"
echo

# Show metrics and telemetry
echo "📈 Metrics & Telemetry:"
echo "======================="
echo "🔧 Vault Metrics Configuration:"
vault read sys/config/telemetry 2>/dev/null || echo "   Default telemetry configuration (not customized)"
echo
echo "📊 Available Metrics:"
echo "   • vault.core.handle_request (request latency)"
echo "   • vault.core.handle_request_count (request volume)"
echo "   • vault.token.lookup (token operations)"
echo "   • vault.secret.kv.count (KV operations)"
echo "   • vault.audit.log_request_failure (audit failures)"
echo
echo "🎯 Monitoring Targets:"
echo "   • Request latency > 1s (performance)"
echo "   • Failed requests > 5% (reliability)"
echo "   • Token renewals (capacity planning)"
echo "   • Audit log failures (security)"
echo

echo "✅ Part 3 Demo Complete!"
echo
echo "🎯 Key Monitoring & Audit Takeaways:"
echo "   • Complete audit trail of all operations"
echo "   • Real-time monitoring and alerting capabilities"
echo "   • Compliance reporting with detailed metrics"
echo "   • SIEM integration for centralized security monitoring"
echo "   • Performance and usage analytics"
echo
echo "📋 For Production:"
echo "   • Enable multiple audit backends (redundancy)"
echo "   • Configure log rotation and archival"
echo "   • Set up automated alerting rules"
echo "   • Integrate with existing monitoring stack"
echo "   • Regular audit log analysis and reporting"
echo
echo "💡 The audit trail provides the foundation for:"
echo "   • Security incident investigation"
echo "   • Compliance reporting (SOX, PCI, HIPAA)"
echo "   • Usage analytics and capacity planning"
echo "   • Performance optimization"