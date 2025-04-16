# Setting up LDAP Authentication with Active Directory.

Main documentation:
https://developer.hashicorp.com/vault/docs/auth/ldap

## Prerequisites
- Vault server is running and unsealed
- You have admin privileges in Vault
- Active Directory server details (hostname, port, bind DN, etc.)
- AD group names that will be mapped to Vault policies
- SSL certificate for secure LDAP connection (recommended)

## Steps

1. Enable the LDAP auth method:
```bash
vault auth enable ldap
```

2. Configure the LDAP connection to your Active Directory:
```bash
vault write auth/ldap/config \
    url="ldaps://<ad-server>:636" \
    userdn="CN=Users,DC=example,DC=com" \
    userattr="sAMAccountName" \
    groupdn="CN=Users,DC=example,DC=com" \
    groupattr="cn" \
    binddn="CN=Service Account,CN=Users,DC=example,DC=com" \
    bindpass="<service-account-password>" \
    insecure_tls=false \
    certificate=@/path/to/certificate.pem \
    starttls=true
```

3. Create policies for your AD groups (using existing admin policy as an example):
```bash
# For administrators group
# we already created this
vault policy write administrators admin_policy.hcl

# For regular users group
vault policy write users user_policy.hcl
```

4. Map AD groups to Vault policies:
```bash
# Map administrators group
vault write auth/ldap/groups/DEV.HashiCorp.Administrators \
    policies=administrators

# Map regular users group
vault write auth/ldap/groups/DEV.HashiCorp.Users \
    policies=users
```

5. Test the LDAP configuration:
```bash
vault login -method=ldap username=<ad-username>
```

6. Rotate root credentials 

The root bindpass can be rotated to a Vault-generated value that is not accessible by the operator. This will ensure that only Vault is able to access the "root" user that Vault uses to manipulate credentials.

```bash
vault write -f auth/ldap/rotate-root
```

## Configuration Details

### Required Parameters
- `url`: LDAP server URL (use ldaps:// for secure connection)
- `userdn`: Base DN for user searches
- `userattr`: Attribute used for username lookup (typically sAMAccountName)
- `groupdn`: Base DN for group searches
- `groupattr`: Attribute used for group membership lookup
- `binddn`: Service account DN for binding to AD
- `bindpass`: Service account password

### Optional Parameters
- `insecure_tls`: Set to true only for testing (not recommended for production)
- `certificate`: Path to CA certificate for LDAPS
- `starttls`: Enable STARTTLS for LDAP
- `tls_min_version`: Minimum TLS version (default: tls12)
- `tls_max_version`: Maximum TLS version (default: tls13)

## Security Recommendations
1. Always use LDAPS (ldaps://) or STARTTLS for secure connections
2. Use a dedicated service account with minimal privileges
3. Store the service account password securely
4. Regularly rotate the service account password
5. Monitor audit logs for authentication attempts
6. Consider enabling MFA for additional security
7. Use strong TLS versions and cipher suites

## Troubleshooting
1. Check Vault logs for connection issues
2. Verify AD service account permissions
3. Test LDAP connectivity using ldapsearch:
```bash
ldapsearch -H ldaps://<ad-server>:636 \
    -D "CN=Service Account,CN=Users,DC=example,DC=com" \
    -w "<service-account-password>" \
    -b "CN=Users,DC=example,DC=com" \
    "(sAMAccountName=<test-user>)"
```

## Next Steps
1. Test authentication with different AD users
2. Verify group membership and policy assignments
3. Set up monitoring and alerting for authentication failures
4. Document the configuration for future reference
5. Consider implementing backup authentication methods 