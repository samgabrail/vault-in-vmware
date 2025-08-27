#!/bin/bash

# LDAP Secrets Engine Setup

echo "Setting up LDAP secrets engine..."

# Wait for services to be ready
sleep 10

# Configure Vault
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root-token"

echo "1. Adding service accounts to LDAP..."

# Create LDIF file with service accounts
cat > /tmp/service_accounts.ldif << 'EOF'
dn: ou=serviceAccounts,dc=demo,dc=local
objectClass: organizationalUnit
ou: serviceAccounts

dn: cn=svc-dba-01,ou=serviceAccounts,dc=demo,dc=local
objectClass: inetOrgPerson
cn: svc-dba-01
sn: DBA Service 01
userPassword: InitialPass01
uid: svc-dba-01

dn: cn=svc-dba-02,ou=serviceAccounts,dc=demo,dc=local
objectClass: inetOrgPerson
cn: svc-dba-02
sn: DBA Service 02
userPassword: InitialPass02
uid: svc-dba-02

dn: cn=svc-dba-03,ou=serviceAccounts,dc=demo,dc=local
objectClass: inetOrgPerson
cn: svc-dba-03
sn: DBA Service 03
userPassword: InitialPass03
uid: svc-dba-03

dn: cn=svc-dba-04,ou=serviceAccounts,dc=demo,dc=local
objectClass: inetOrgPerson
cn: svc-dba-04
sn: DBA Service 04
userPassword: InitialPass04
uid: svc-dba-04

dn: cn=svc-dba-05,ou=serviceAccounts,dc=demo,dc=local
objectClass: inetOrgPerson
cn: svc-dba-05
sn: DBA Service 05
userPassword: InitialPass05
uid: svc-dba-05

dn: cn=svc-dba-06,ou=serviceAccounts,dc=demo,dc=local
objectClass: inetOrgPerson
cn: svc-dba-06
sn: DBA Service 06
userPassword: InitialPass06
uid: svc-dba-06

dn: cn=svc-web-01,ou=serviceAccounts,dc=demo,dc=local
objectClass: inetOrgPerson
cn: svc-web-01
sn: Web Service 01
userPassword: WebPass01
uid: svc-web-01

dn: cn=svc-web-02,ou=serviceAccounts,dc=demo,dc=local
objectClass: inetOrgPerson
cn: svc-web-02
sn: Web Service 02
userPassword: WebPass02
uid: svc-web-02

dn: cn=svc-web-03,ou=serviceAccounts,dc=demo,dc=local
objectClass: inetOrgPerson
cn: svc-web-03
sn: Web Service 03
userPassword: WebPass03
uid: svc-web-03
EOF

# Copy LDIF file to container and add entries
docker cp /tmp/service_accounts.ldif demo-openldap:/tmp/service_accounts.ldif
docker exec demo-openldap ldapadd -x -D "cn=admin,dc=demo,dc=local" -w admin123 -f /tmp/service_accounts.ldif

echo "2. Enabling LDAP secrets engine..."
vault secrets enable ldap 2>/dev/null || echo "   LDAP secrets engine already enabled"

echo "3. Configuring LDAP connection..."
vault write ldap/config \
    binddn='cn=admin,dc=demo,dc=local' \
    bindpass='admin123' \
    url='ldap://demo-openldap:389' \
    userdn='ou=serviceAccounts,dc=demo,dc=local'

echo "4. Creating role-based service account libraries..."

echo "   Creating database admin library..."
vault write ldap/library/database-admins \
    service_account_names='svc-dba-01,svc-dba-02,svc-dba-03,svc-dba-04,svc-dba-05,svc-dba-06' \
    ttl='1h' \
    max_ttl='24h' \
    disable_check_in_enforcement=false

echo "   Creating web admin library..."
vault write ldap/library/web-admins \
    service_account_names='svc-web-01,svc-web-02,svc-web-03' \
    ttl='1h' \
    max_ttl='24h' \
    disable_check_in_enforcement=false

echo ""
echo "✅ LDAP secrets engine setup complete!"
echo ""
echo "Service accounts created in LDAP:"
echo "  • Database: svc-dba-01 through svc-dba-06"
echo "  • Web:      svc-web-01 through svc-web-03"
echo ""
echo "Libraries created:"
echo "  • ldap/library/database-admins (svc-dba-01,02,03,04,05,06)"
echo "  • ldap/library/web-admins      (svc-web-01,02,03)"
echo ""
echo "Run ./demo.sh to see the multi-library LDAP check-in/check-out demo"