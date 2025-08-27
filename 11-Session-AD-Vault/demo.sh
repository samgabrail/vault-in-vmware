#!/bin/bash

#  AD/LDAP Check-In/Check-Out Demo using Vault's LDAP Secrets Engine
# Uses the vault LDAP library check-out/check-in functionality

# Configuration
VAULT_ADDR=${VAULT_ADDR:-"http://127.0.0.1:8200"}
VAULT_TOKEN="root-token"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'



# Show LDAP library status
show_ldap_library_status() {
    echo ""
    echo "Database Admins Library Status:"
    vault read ldap/library/database-admins/status | grep -E "svc-" | while read account status; do
        if echo "$status" | grep -q "available:true"; then
            echo -e "  ✅ $account: Available"
        else
            echo -e "  🔒 $account: Checked out"
        fi
    done
    
    echo ""
    echo "Web Admins Library Status:"
    vault read ldap/library/web-admins/status | grep -E "svc-" | while read account status; do
        if echo "$status" | grep -q "available:true"; then
            echo -e "  ✅ $account: Available"
        else
            echo -e "  🔒 $account: Checked out"
        fi
    done
    echo ""
}

# Cleanup on exit
cleanup() {
    echo ""
    echo "Stopping all nodes..."
    RUNNING=false
    kill $(jobs -p) 2>/dev/null
    wait
    echo ""
    echo "Demo stopped"
    exit 0
}

# Simple checkout and checkin demo
simple_checkout() {
    local library=$1
    local node=$2
    
    echo ""
    echo "Command: ${YELLOW}vault write -force ldap/library/$library/check-out${NC}"
    local response=$(vault write -format=json -force ldap/library/$library/check-out 2>&1)
    
    if echo "$response" | jq -e '.data' > /dev/null 2>&1; then
        local username=$(echo "$response" | jq -r '.data.service_account_name')
        local password=$(echo "$response" | jq -r '.data.password')
        
        echo -e "${GREEN}✓ Checked out:${NC} $username from $library"
        echo -e "  Password: ${password:0:20}..."
        
        # Test authentication
        echo -e "  Testing LDAP auth..."
        local auth_result=$(docker exec demo-openldap ldapwhoami -x \
            -H "ldap://localhost" \
            -D "cn=$username,ou=serviceAccounts,dc=demo,dc=local" \
            -w "$password" 2>&1)
        
        if echo "$auth_result" | grep -q "dn:cn=$username"; then
            echo -e "  ${GREEN}✓ LDAP AUTH SUCCESS${NC}"
        fi
        
        # Return username:library for later check-in (to stderr so it doesn't interfere)
        echo "$username:$library" >&2
    else
        echo -e "${RED}✗ Check-out failed${NC}"
    fi
}

# Simple check-in
simple_checkin() {
    local username=$1
    local library=$2
    
    echo ""
    echo "Command: ${YELLOW}vault write ldap/library/$library/check-in service_account_names=\"$username\"${NC}"
    vault write ldap/library/$library/check-in service_account_names="$username"
    echo -e "${GREEN}✓ Checked in:${NC} $username to $library"
}

# Main demo using LDAP secrets engine
main() {
    echo ""
    echo "=============================================="
    echo "   LDAP Secrets Engine Check-Out/Check-In"
    echo "=============================================="
    echo ""
    
    # Set Vault environment
    export VAULT_ADDR VAULT_TOKEN
    
    echo "1. Checking out Database Service Accounts:"
    echo "==========================================="
    echo ""
    echo -e "Command: ${YELLOW}vault write -force ldap/library/database-admins/check-out${NC}"
    local db_checkout1=$(vault write -format=json -force ldap/library/database-admins/check-out)
    echo "$db_checkout1" | jq -r '. | "Key                     Value\n---                     -----\nlease_id                \(.lease_id)\nlease_duration          \(.lease_duration)\nlease_renewable         \(.lease_renewable)\npassword                \(.data.password)\nservice_account_name    \(.data.service_account_name)"'
    
    local db_user1=$(echo "$db_checkout1" | jq -r '.data.service_account_name')
    local db_pass1=$(echo "$db_checkout1" | jq -r '.data.password')
    echo ""
    
    echo -e "Command: ${YELLOW}vault write -force ldap/library/database-admins/check-out${NC}" 
    vault write -force ldap/library/database-admins/check-out
    echo ""
    
    echo "2. Checking out Web Service Accounts:"
    echo "======================================"
    echo ""
    echo -e "Command: ${YELLOW}vault write -force ldap/library/web-admins/check-out${NC}"
    vault write -force ldap/library/web-admins/check-out
    echo ""
    
    echo -e "Command: ${YELLOW}vault write -force ldap/library/web-admins/check-out${NC}"
    vault write -force ldap/library/web-admins/check-out
    echo ""
    
    echo "3. Testing LDAP Authentication with Checked Out Credentials:"
    echo "==========================================================="
    echo ""
    echo "Testing authentication for $db_user1..."
    local auth_result=$(docker exec demo-openldap ldapwhoami -x \
        -H "ldap://localhost" \
        -D "cn=$db_user1,ou=serviceAccounts,dc=demo,dc=local" \
        -w "$db_pass1" 2>&1)
    
    if echo "$auth_result" | grep -q "dn:cn=$db_user1"; then
        echo -e "${GREEN}✓ LDAP AUTH SUCCESS:${NC} $db_user1 authenticated successfully with checked out password"
    else
        echo -e "${RED}✗ LDAP AUTH FAILED:${NC} Could not authenticate $db_user1"
    fi
    echo ""
    
    echo "4. Current Status - Accounts Checked Out:"
    echo "========================================="
    show_ldap_library_status
    
    echo "5. Checking In All Accounts (Password Rotation Happens Here):"
    echo "============================================================="
    echo ""
    echo -e "Command: ${YELLOW}vault write ldap/library/database-admins/check-in service_account_names=\"svc-dba-01,svc-dba-02\"${NC}"
    vault write ldap/library/database-admins/check-in service_account_names="svc-dba-01,svc-dba-02"
    echo ""
    
    echo -e "Command: ${YELLOW}vault write ldap/library/web-admins/check-in service_account_names=\"svc-web-01,svc-web-02\"${NC}"
    vault write ldap/library/web-admins/check-in service_account_names="svc-web-01,svc-web-02"
    echo ""
    
    echo "6. Final Status - All Accounts Available:"
    echo "========================================="
    show_ldap_library_status
    echo ""
    
    echo "✅ Demo Complete!"
    echo ""
    echo "Key Points:"
    echo "- Password rotation occurs upon check-in (not check-out)"
    echo "- Each application gets unique service account"
    echo "- Vault prevents credential conflicts automatically"
}


# Parse arguments
case "${1:-}" in
    "status")
        export VAULT_ADDR VAULT_TOKEN
        show_ldap_library_status
        ;;
    "-h"|"--help")
        echo "Usage: $0 [status]"
        echo ""
        echo "This demo uses Vault's LDAP secrets engine"
        echo "with multiple role-based libraries:"
        echo "  • database-admins (svc-dba-01,02,03,04,05,06)"
        echo "  • web-admins      (svc-web-01,02,03)"
        echo ""
        echo "Commands:"
        echo "  (no args)  - Start the multi-library demo"
        echo "  status     - Check all LDAP library statuses"
        echo ""
        echo "Make sure you've run ./setup.sh first!"
        ;;
    *)
        export VAULT_ADDR VAULT_TOKEN
        main
        ;;
esac