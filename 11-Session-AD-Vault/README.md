# AD/LDAP Check-In/Check-Out Demo

Demonstration of Vault's **LDAP secrets engine** with service account check-in/check-out to prevent credential conflicts in multi-node applications.

## What This Demo Uses

**✅ Vault LDAP Secrets Engine:**
- `vault secrets enable ldap`
- `vault write ldap/library/dba-library/check-out`  
- `vault write ldap/library/dba-library/check-in service_account_names=...`

**✅ OpenLDAP Server:**
- LDAP directory with service accounts
- LDAP authentication and password rotation
- Authentication verification with rotated passwords

**✅ Vault Features:**
- Service account libraries
- Built-in check-in/check-out enforcement  
- Automatic password rotation by Vault
- LDAP authentication testing with rotated credentials

## The Problem
Multiple application nodes using the same service account credentials can conflict. Manual password management is slow and error-prone.

## The Solution  
Vault's LDAP secrets engine with service account libraries where:
- Each node gets a unique service account from the pool
- Vault automatically rotates passwords on check-out and check-in
- Built-in enforcement prevents double check-out
- Pool exhaustion protection when all accounts are in use

## Quick Start

```bash
# 1. Start infrastructure (Vault + OpenLDAP)
docker-compose up -d

# 2. Setup LDAP secrets engine and library
./setup.sh

# 3. Run the demo
./demo.sh
```

## What You'll See

The demo demonstrates the complete lifecycle:

**1. Database Service Account Check-Outs:**
```
Command: vault write -force ldap/library/database-admins/check-out
Key                     Value
---                     -----
lease_id                ldap/library/database-admins/check-out/uVQJsu4U7dp0SY0loPAVKne0
lease_duration          3600
lease_renewable         null
password                VgIUOxM9tjycAYcAxfgIIuJNi4MHApewWgtQHs7lKxqLw7sDugV80jqX1WMsqvO9
service_account_name    svc-dba-01

Command: vault write -force ldap/library/database-admins/check-out
Key                     Value
---                     -----
lease_id                ldap/library/database-admins/check-out/IpQnbipLKq8QOkwc2LyYcPqj
lease_duration          1h
lease_renewable         true
password                T3hyzEJDAWqnJmnTtvlU9IwuVGA4Zmpm4DnDXDvOs5qxpHrGS6gOSVDAIlW2oAvd
service_account_name    svc-dba-02
```

**2. Web Service Account Check-Outs:**
```
Command: vault write -force ldap/library/web-admins/check-out
Key                     Value
---                     -----
lease_id                ldap/library/web-admins/check-out/MUx2yafQZwgPvVAIYC7SZ01D
lease_duration          1h
lease_renewable         true
password                zfWcuTHAau4tpv7N5Kl6NcgTZMMDu49nj1AibzdjJ4p3elEYdHzSZdOvhTosyggL
service_account_name    svc-web-01

Command: vault write -force ldap/library/web-admins/check-out
Key                     Value
---                     -----
lease_id                ldap/library/web-admins/check-out/OaQCEKg8rpmGWoc8cMhbj0fY
lease_duration          1h
lease_renewable         true
password                ZTxw8jTrumj9MiJLV3xQf5vgw44vuB89187BnK2LZfRRAaXRCuMNDhjSWI6TXZAH
service_account_name    svc-web-02
```

**3. LDAP Authentication Test:**
```
Testing authentication for svc-dba-01...
✓ LDAP AUTH SUCCESS: svc-dba-01 authenticated successfully with checked out password
```

**4. Library Status - Accounts Checked Out:**
```
Database Admins Library Status:
  🔒 svc-dba-01: Checked out
  🔒 svc-dba-02: Checked out
  ✅ svc-dba-03: Available
  ✅ svc-dba-04: Available
  ✅ svc-dba-05: Available
  ✅ svc-dba-06: Available

Web Admins Library Status:
  🔒 svc-web-01: Checked out
  🔒 svc-web-02: Checked out
  ✅ svc-web-03: Available
```

**5. Check-In with Password Rotation:**
```
Command: vault write ldap/library/database-admins/check-in service_account_names="svc-dba-01,svc-dba-02"
Key          Value
---          -----
check_ins    [svc-dba-01 svc-dba-02]

Command: vault write ldap/library/web-admins/check-in service_account_names="svc-web-01,svc-web-02"
Key          Value
---          -----
check_ins    [svc-web-01 svc-web-02]
```

**6. Final Status - All Accounts Available:**
```
Database Admins Library Status:
  ✅ svc-dba-01: Available
  ✅ svc-dba-02: Available
  ✅ svc-dba-03: Available
  ✅ svc-dba-04: Available
  ✅ svc-dba-05: Available
  ✅ svc-dba-06: Available

Web Admins Library Status:
  ✅ svc-web-01: Available
  ✅ svc-web-02: Available
  ✅ svc-web-03: Available
```

## Vault Commands Used

The demo uses these **Vault LDAP secrets engine** commands:

```bash
# Enable LDAP secrets engine
vault secrets enable ldap

# Configure LDAP connection
vault write ldap/config \
    binddn='cn=admin,dc=demo,dc=local' \
    bindpass='admin123' \
    url='ldap://demo-openldap:389' \
    userdn='ou=serviceAccounts,dc=demo,dc=local'

# Create service account library  
vault write ldap/library/dba-library \
    service_account_names='svc-dba-01,svc-dba-02,...' \
    ttl='1h' \
    max_ttl='24h'

# Check out (what the demo does)
vault write ldap/library/dba-library/check-out

# Check in (what the demo does)
vault write ldap/library/dba-library/check-in \
    service_account_names='svc-dba-01'
```

## Files

- `docker-compose.yml` - Infrastructure (Vault + OpenLDAP)
- `setup.sh` - Configure LDAP secrets engine
- `demo.sh` - Multi-node demo using Vault LDAP API
- `cleanup.sh` - Clean everything up

## Commands

- `./demo.sh` - Run the demonstration using LDAP with authentication testing
- `./demo.sh status` - Check LDAP library status
- `./cleanup.sh` - Clean everything up

### Manual LDAP Authentication Testing

You can manually test LDAP authentication with checked-out credentials:

```bash
# 1. Check out a service account
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root-token"
vault write -format=json -force ldap/library/database-admins/check-out

# 2. Test authentication with the returned credentials
docker exec demo-openldap ldapwhoami -x \
  -H "ldap://localhost" \
  -D "cn=svc-dba-01,ou=serviceAccounts,dc=demo,dc=local" \
  -w "YOUR-RETURNED-PASSWORD"
```

**Successful authentication shows:**
```
# ldapwhoami output:
dn:cn=svc-dba-01,ou=serviceAccounts,dc=demo,dc=local
```

This proves the checked-out password works for actual LDAP authentication!

## UI Access

### Vault UI
You can interact with the LDAP libraries through Vault's web interface:

1. **Open browser:** http://localhost:8200
2. **Login with token:** `root-token`
3. **Navigate:** Secrets engines → ldap → libraries
4. **Try check-out/check-in:** Click on any library (database-admins, web-admins) to manually check out and check in service accounts

### phpLDAPadmin UI
You can also browse the LDAP directory directly:

1. **Open browser:** http://localhost:8080
2. **Login DN:** `cn=admin,dc=demo,dc=local`
3. **Password:** `admin123`
4. **Browse:** Navigate to `ou=serviceAccounts,dc=demo,dc=local` to see the service accounts
5. **Verify:** Check that passwords are actually rotated by Vault in the LDAP directory

This provides visual access to both Vault's management interface and the underlying LDAP directory structure.

## Conflict Prevention & Pool Management

**✅ Built-in Multi-Node Protection:**
- Different entities automatically get different service accounts
- No risk of credential conflicts between application nodes
- Pool exhaustion prevents over-allocation

**Example Behavior:**
```bash
# Entity 1 checks out
vault write -force ldap/library/dba-library/check-out
# Returns: svc-dba-01

# Entity 2 checks out  
vault write -force ldap/library/dba-library/check-out
# Returns: svc-dba-02 (different account!)

# When pool is exhausted
vault write -force ldap/library/dba-library/check-out
# Error: "No service accounts available for check-out."
```

**Demo Verification:**
- 3 concurrent nodes each get unique accounts (`svc-dba-01`, `svc-dba-02`, `svc-dba-03`)
- password rotation in LDAP directory confirmed
- Service accounts returned to pool on check-in

## Service Account Selection & Multiple Libraries

**❌ Cannot Specify Individual Accounts:**
- No way to request a specific service account by name
- Vault automatically selects the next available account from the pool
- Parameters like `service_account_name` are ignored

**✅ Use Multiple Libraries for Choice:**
```bash
# Role-based libraries for different access types
vault write ldap/library/database-admins \
    service_account_names='svc-dba-01,svc-dba-02,svc-dba-03,svc-dba-04,svc-dba-05,svc-dba-06'

vault write ldap/library/web-admins \
    service_account_names='svc-web-01,svc-web-02,svc-web-03'

# Applications choose appropriate library
vault write -force ldap/library/database-admins/check-out  # Gets DB account
vault write -force ldap/library/web-admins/check-out       # Gets web account
```

**Key Constraints:**
- Each service account can only belong to **one library**
- Library = Service Account Type/Role
- Better security through role-based separation

## Authentication Verification

The demo includes full LDAP authentication testing:

**Authentication Method Used:**
- `ldapwhoami` - Verifies the account can authenticate

**Complete Lifecycle Demonstrated:**
1. Vault checks out service account (existing password)
2. Application authenticates to LDAP with current password ✅
3. Application performs work with authenticated credentials
4. Application checks account back into library
5. **Password rotation occurs upon check-in** 🔄

**Password Rotation Timing:**
- **Check-out**: Uses existing password (no rotation)
- **Check-in**: Password automatically rotated by Vault
- **TTL Expiry**: Additional rotation when lease expires