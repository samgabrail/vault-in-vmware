# Setting up Userpass Authentication and Admin Account

## Prerequisites
- Vault server is running and unsealed
- You have root token or sufficient privileges to enable auth methods and create policies

## Steps

1. First, enable the userpass auth method:
```bash
vault auth enable userpass
```

2. Create the admin policy from the admin_policy.hcl file:
```bash
vault policy write admin admin_policy.hcl
```

3. Create an admin user with the admin policy:
```bash
vault write auth/userpass/users/admin \
    password="<choose-a-strong-password>" \
    policies="admin"
```

4. Verify the user was created:
```bash
vault read auth/userpass/users/admin
```

5. Test the login with the new admin user:
```bash
vault login -method=userpass username=admin
```

## Important Notes
- Replace `<choose-a-strong-password>` with a strong password of your choice
- Make sure to securely store the password
- The admin user will have all the capabilities defined in the admin_policy.hcl
- You can create additional users with different policies as needed

## Security Recommendations
- Consider enabling MFA for the userpass auth method
- Rotate passwords regularly
- Monitor audit logs for any suspicious activity
- Consider using a password manager to store the admin credentials securely 