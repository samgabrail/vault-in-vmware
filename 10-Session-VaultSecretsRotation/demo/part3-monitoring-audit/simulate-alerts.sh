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
