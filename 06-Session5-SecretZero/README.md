# Jenkins Integration with HashiCorp Vault

This guide provides instructions for setting up Jenkins to authenticate with HashiCorp Vault using AppRole for multiple applications.

## Table of Contents
- [Overview](#overview)
- [Setting Up Multi-Application Access](#setting-up-multi-application-access)
- [Configuring Jenkins Vault Plugin](#configuring-jenkins-vault-plugin)
- [Using Vault Secrets in Jenkinsfiles](#using-vault-secrets-in-jenkinsfiles)
- [Best Practices](#best-practices)
- [Scaling Considerations](#scaling-considerations)
- [SecretID Rotation Strategy](#secretid-rotation-strategy)

## Overview

AppRole is designed for machine-to-machine authentication and is ideal for Jenkins integration. This guide demonstrates how to set up separate AppRoles for different applications (app1 and app2) using the Jenkins Vault Plugin.

## Setting Up Multi-Application Access

### 1. Enable AppRole Auth Method

```bash
# If not already enabled
vault auth enable approle
```

### 2. Create Application-Specific Policies

Create separate policies for each application to enforce least privilege:

**app1.hcl**:
```hcl
# Access to app1 secrets (KV v2)
path "secrets/data/app1" {
  capabilities = ["read"]
}

path "secrets/metadata/app1" {
  capabilities = ["read", "list"]
}
```

**app2.hcl**:
```hcl
# Access to app2 secrets (KV v2)
path "secrets/data/app2" {
  capabilities = ["read"]
}

path "secrets/metadata/app2" {
  capabilities = ["read", "list"]
}
```

Register the policies:
```bash
vault policy write app1 app1.hcl
vault policy write app2 app2.hcl
```

### 3. Create AppRoles for Each Application

```bash
# Create app1 AppRole
vault write auth/approle/role/app1 \
    token_policies="app1" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=720h \
    secret_id_bound_cidrs="10.0.0.0/24,192.168.1.0/24" \
    token_bound_cidrs="10.0.0.0/24" \
    secret_id_num_uses=0

# Create app2 AppRole
vault write auth/approle/role/app2 \
    token_policies="app2" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=720h \
    secret_id_bound_cidrs="10.0.0.0/24,192.168.1.0/24" \
    token_bound_cidrs="10.0.0.0/24" \
    secret_id_num_uses=0
```


#### CIDR Block Restrictions in Vault AppRole

There are two ways to implement CIDR block restrictions in Vault's AppRole authentication method:

##### 1. Secret ID CIDR Binding
```
secret_id_bound_cidrs (array: []) - Comma-separated string or list of CIDR blocks; if set, specifies blocks of IP addresses which can perform the login operation.
```

This restricts **which IP addresses can use the SecretID to log in**. This is a restriction on the authentication process itself.

##### 2. Token CIDR Binding
```
token_bound_cidrs (array: [] or comma-delimited string: "") - List of CIDR blocks; if set, specifies blocks of IP addresses which can authenticate successfully, and ties the resulting token to these blocks as well.
```

This restricts **where the resulting token can be used** after successful authentication. The token will only be usable from the specified IP ranges.

##### Example Configuration

```shell
# Create an AppRole with CIDR restrictions
vault write auth/approle/role/restricted-role \
    secret_id_bound_cidrs="10.0.0.0/24,192.168.1.0/24" \
    token_bound_cidrs="10.0.0.0/24" \
    token_policies="app-policy" \
    bind_secret_id=true
```

This creates an AppRole where:
- The SecretID can only be used to log in from the 10.0.0.0/24 or 192.168.1.0/24 networks
- Once authenticated, the resulting token can only be used from the 10.0.0.0/24 network

### 4. Get RoleIDs and Generate SecretIDs

```bash
# Get app1 RoleID
vault read auth/approle/role/app1-approle/role-id

# Get app2 RoleID
vault read auth/approle/role/app2-approle/role-id

# Generate app1 SecretID
vault write -f auth/approle/role/app1-approle/secret-id

# Generate app2 SecretID
vault write -f auth/approle/role/app2-approle/secret-id
```

Every AppRole has only 1 role-id but can generate multiple secret-ids.

## Configuring Jenkins Vault Plugin

### 1. Install the HashiCorp Vault Plugin

1. Navigate to **Jenkins Dashboard > Manage Jenkins > Plugins > Available**
2. Search for "HashiCorp Vault"
3. Install the plugin and restart Jenkins

### 2. Configure the Vault Plugin

1. Go to **Jenkins Dashboard > Manage Jenkins > System**
2. Scroll to the **HashiCorp Vault Plugin** section
3. Configure the Vault server:
   - **Vault URL**: Enter your Vault server URL
   - **Skip SSL Verification**: Only check if using self-signed certs (not recommended for production)
   - **Timeout**: Set to 60 seconds
   - **Max Retries**: Set to 5

### 3. Add Vault Credentials to Jenkins

1. Add a credential for app1:
   - Go to **Jenkins Dashboard > Manage Jenkins > Credentials > System > Global credentials**
   - Click **Add Credentials**
   - Select **Vault App Role Credential** from the dropdown
   - Enter:
     - **ID**: `app1-approle-credentials`
     - **Description**: "Vault AppRole for app1 application"
     - **Role ID**: Enter the app1 Role ID
     - **Secret ID**: Enter the app1 Secret ID
   - Click **OK**

2. Add a credential for app2:
   - Go to **Jenkins Dashboard > Manage Jenkins > Credentials > System > Global credentials**
   - Click **Add Credentials**
   - Select **Vault App Role Credential** from the dropdown
   - Enter:
     - **ID**: `app2-approle-credentials`
     - **Description**: "Vault AppRole for app2 application"
     - **Role ID**: Enter the app2 Role ID
     - **Secret ID**: Enter the app2 Secret ID
   - Click **OK**

## Using Vault Secrets in Jenkinsfiles

### Example for app1 Application

```groovy
pipeline {
    agent { label 'jenkins-agent' }
    options { timestamps() }
    
    stages {
        stage('Fetch app1 Secrets') {
            steps {
                withVault(
                    configuration: [
                        vaultCredentialId: 'app1-approle-credentials',
                        engineVersion: 2 // This specifies KV v2
                    ],
                    vaultSecrets: [
                        [path: 'secrets/data/app1', secretValues: [
                            [envVar: 'DB_PASSWORD', vaultKey: 'password'],
                            [envVar: 'API_KEY', vaultKey: 'api_key']
                        ]]
                    ]
                ) {
                    // Use secrets securely
                    sh 'echo "Connecting to database..."'
                    // Never echo the actual secrets
                }
            }
        }
    }
}
```

### Example for app2 Application

```groovy
pipeline {
    agent { label 'jenkins-agent' }
    options { timestamps() }
    
    stages {
        stage('Fetch app2 Secrets') {
            steps {
                withVault(
                    configuration: [
                        vaultCredentialId: 'app2-approle-credentials',
                        engineVersion: 2
                    ],
                    vaultSecrets: [
                        [path: 'secrets/data/app2', secretValues: [
                            [envVar: 'API_ENDPOINT', vaultKey: 'api_endpoint'],
                            [envVar: 'API_KEY', vaultKey: 'api_key'],
                            [envVar: 'DB_PASSWORD', vaultKey: 'db_password']
                        ]]
                    ]
                ) {
                    // Use app2 secrets securely
                    sh 'echo "Connecting to app2 API..."'
                    sh 'echo "API endpoint: $API_ENDPOINT"'
                    // Never echo the actual secret values
                }
            }
        }
    }
}
```

### Using Multiple Applications in a Single Pipeline

You can also access secrets from multiple applications in a single pipeline:

```groovy
pipeline {
    agent { label 'jenkins-agent' }
    options { timestamps() }
    
    stages {
        stage('Fetch Multiple Secrets') {
            steps {
                withVault([
                    configuration: [
                        engineVersion: 2
                    ],
                    vaultSecrets: [
                        [
                            path: 'secrets/data/app1',
                            credentialsId: 'app1-approle-credentials', 
                            secretValues: [
                                [envVar: 'APP1_DB_PASSWORD', vaultKey: 'password']
                            ]
                        ],
                        [
                            path: 'secrets/data/app2',
                            credentialsId: 'app2-approle-credentials', 
                            secretValues: [
                                [envVar: 'APP2_API_KEY', vaultKey: 'api_key']
                            ]
                        ]
                    ]
                ]) {
                    // Use secrets from both applications
                    sh 'echo "Working with multiple applications..."'
                    // Your build and deployment steps here
                }
            }
        }
    }
}
```

## Best Practices

1. **Secret Zero Management**:
   - Store RoleID and SecretID in Jenkins credentials
   - Use different AppRoles for different applications/teams

2. **SecretID Rotation**:
   - Implement regular rotation of SecretIDs
   - Set appropriate TTLs on SecretIDs (e.g., 30 days)
   - The plugin does not automatically rotate SecretIDs

3. **Token Lifecycle**:
   - **Set appropriate TTLs on tokens (e.g., 1-4 hours)**: When creating AppRoles, the `token_ttl` parameter defines how long the Vault tokens are valid after authentication. Short-lived tokens (1-4 hours) minimize the risk if a token is compromised.
   - **Enable token renewal in plugin configuration**: The Jenkins Vault Plugin can automatically renew tokens before they expire. This is configured in the Jenkins system configuration under the Vault Plugin section by checking the "Vault Token Renewal" option. This ensures uninterrupted access to Vault without requiring re-authentication.

4. **Security Considerations**:
   - Use HTTPS for Vault communication
   - Restrict access to Jenkins credential management
   - Never echo secrets in build logs

5. **Path Management**:
   - Use clear path structures in Vault
   - Follow the principle of least privilege
   - Use separate paths for different applications

6. **KV v2 Path Structure**:
   - Remember that KV v2 requires `/data/` in the path (`secrets/data/mykey`)
   - When configuring policies, include both data and metadata paths
   - The plugin handles path formatting when `engineVersion: 2` is specified

7. **Plugin vs. Manual Script Approach**:
   Using the Jenkins Vault Plugin offers significant advantages over manual shell scripts for Vault authentication:

   - **Secure Credential Handling**: The plugin handles secrets securely without exposing them as environment variables, which can be accidentally logged.
   
   - **Simplified Configuration**: Dramatically reduces the amount of code needed in Jenkinsfiles. Compare the ~50 lines of manual script to the ~10 lines when using the plugin.
   
   - **Automatic Token Management**: The plugin handles token acquisition, renewal, and revocation automatically, reducing the risk of expired tokens disrupting builds.
   
   - **No Hardcoded Values**: Eliminates the need for hardcoding RoleIDs or Vault addresses in pipeline scripts.
   
   - **Error Handling**: Built-in error handling and retries provide more reliable Vault interactions.
   
   - **Path Handling**: The plugin correctly formats paths for KV v2 with the `engineVersion: 2` setting, avoiding manual path construction.
   
   - **Centralized Configuration**: Global settings are managed in Jenkins configuration rather than duplicated across pipelines.
   
   - **Reduced Maintenance**: Less custom code means fewer things that can break when Vault or Jenkins is upgraded.
   
   - **Security Best Practices**: The plugin architecture encourages security best practices by design rather than relying on developers to implement them correctly.

## Scaling Considerations

When scaling this solution to dozens or hundreds of applications, consider the following:

### What Scales Well

1. **Plugin Architecture**: The Jenkins Vault Plugin is designed for enterprise-scale usage and handles multiple credentials efficiently.

2. **Least Privilege Model**: The one-AppRole-per-application design maintains strong security boundaries as you add more applications.

3. **Path Structure**: KV v2's path structure works well with hundreds of applications, keeping secrets properly organized.

4. **Token Management**: The plugin's automatic token renewal system works just as efficiently with 1 or 100 applications.

### Required Adjustments for Scale

1. **Policy Automation**: 
   - Use templating tools like Terraform for policy generation
   - Implement CI/CD pipelines to automate policy creation and deployment
   - Adopt standardized naming conventions to facilitate automation

   Example Terraform for policy generation:
   ```hcl
   resource "vault_policy" "application_policies" {
     for_each = var.applications
     
     name   = each.key
     policy = templatefile("${path.module}/templates/app-policy.tpl", {
       app_name = each.key
     })
   }
   ```

2. **AppRole Creation**:
   - Create batch scripts or use Terraform to create AppRoles programmatically
   - Use consistent parameters (like TTLs) across applications
   - Automate the RoleID and SecretID generation process

3. **Credential Management**:
   - Use Jenkins Configuration as Code (JCasC) to define credentials
   - Organize with Jenkins Folder-level credentials for team-based management
   - Consider implementing a credential provider for dynamic credential generation

4. **Organizational Structure**:
   - Group applications by team or department in both Vault and Jenkins
   - Utilize Jenkins folders to organize jobs by application
   - Implement RBAC in Jenkins to match Vault access controls

5. **Secret Rotation**:
   - Implement centralized rotation schedules
   - Build automated tools for SecretID rotation across many applications
   - Consider a rotation service that handles multiple applications

### Implementation Strategy for Large Scale

For environments with many applications, we recommend:

1. **Standardize First**: Establish naming conventions and path standards before scaling
2. **Automate Everything**: Script all Vault and Jenkins configuration tasks
3. **Centralize Monitoring**: Implement comprehensive monitoring for credential issues
4. **Document Processes**: Create clear procedures for onboarding new applications
5. **Test at Scale**: Validate performance with a representative number of applications

## SecretID Rotation Strategy

Managing SecretID rotation for 100+ applications requires careful planning. This section outlines strategies to balance security with operational efficiency.

### Balancing Security with Practicality

#### Option 1: Automated Rotation System (Recommended)

For true security at scale, implement an automated rotation system:

```bash
# Example automated rotation script pseudocode
for app in $(get_application_list); do
  # Get new SecretID
  new_secret_id=$(vault write -f -field=secret_id auth/approle/role/${app}-approle/secret-id)
  
  # Update in Jenkins via API
  curl -X POST "${JENKINS_URL}/credentials/store/system/domain/_/credential/${app}-approle-credentials/updateSecretId" \
    --user "${JENKINS_ADMIN}:${JENKINS_TOKEN}" \
    --data-urlencode "secretId=${new_secret_id}"
  
  log "Rotated SecretID for ${app}"
done
```

**Benefits:**
- Maintains security with regular rotation
- Fully automated, minimal human intervention
- Can be scheduled at different intervals for different risk levels

#### Option 2: Tiered TTL Approach

Balance security and operational overhead with a tiered approach:

1. **Critical applications** (financial, PII): 30-90 day TTLs with scheduled rotation
2. **Standard applications**: 180-365 day TTLs with annual rotation
3. **Low-risk applications**: Very long TTLs (1-2 years)

```bash
# Create high-security AppRole
vault write auth/approle/role/payment-service-approle \
    token_policies="payment-service" \
    secret_id_ttl=2160h  # 90 days

# Create standard AppRole 
vault write auth/approle/role/content-management-approle \
    token_policies="content-management" \
    secret_id_ttl=8760h  # 365 days
```

### Implementation Recommendations

1. **Centralized Rotation Service**:
   - Build a dedicated microservice responsible for SecretID rotation
   - Use Vault's token to manage SecretIDs and Jenkins API to update credentials
   - Schedule different rotation schedules based on security tiers

2. **Jenkins Credential Provider Plugin**:
   - Consider developing a custom credential provider for Jenkins that fetches credentials dynamically
   - This eliminates the need to store SecretIDs in Jenkins at all

3. **Monitoring and Alerting**:
   - Track SecretID expiration dates across all applications
   - Set up alerts for upcoming expirations
   - Monitor rotation failures and implement automated retries

4. **Overlapping Validity Periods**:
   - When rotating SecretIDs, implement a grace period where both old and new are valid
   - This prevents disruption if some components still use the old SecretID

5. **Documentation and Audit**:
   - Maintain clear documentation of rotation policies for each application tier
   - Keep audit logs of all rotation activities
   - Regularly review rotation policies as part of security governance

### Long TTLs vs. Rotation

While long TTLs (like 1+ years) are operationally simpler, we recommend a balanced approach where:

1. You implement automated rotation as a security best practice
2. You use longer TTLs (6-12 months) as a fallback to prevent unexpected expiration
3. You apply more frequent rotation to your highest-risk applications

With proper automation, the operational overhead of rotation can be minimized while still maintaining good security hygiene.
