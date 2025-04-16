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

AppRole is designed for machine-to-machine authentication and is ideal for Jenkins integration. This guide demonstrates how to set up separate AppRoles for different applications (dbit and healthcare) using the Jenkins Vault Plugin.

## Setting Up Multi-Application Access

### 1. Enable AppRole Auth Method

```bash
# If not already enabled
vault auth enable approle
```

### 2. Create Application-Specific Policies

Create separate policies for each application to enforce least privilege:

**dbit.hcl**:
```hcl
# Access to dbit secrets (KV v2)
path "secrets/data/dbit" {
  capabilities = ["read"]
}

path "secrets/metadata/dbit" {
  capabilities = ["read", "list"]
}
```

**healthcare.hcl**:
```hcl
# Access to healthcare secrets (KV v2)
path "secrets/data/healthcare" {
  capabilities = ["read"]
}

path "secrets/metadata/healthcare" {
  capabilities = ["read", "list"]
}
```

Register the policies:
```bash
vault policy write dbit dbit.hcl
vault policy write healthcare healthcare.hcl
```

### 3. Create AppRoles for Each Application

```bash
# Create dbit AppRole
vault write auth/approle/role/dbit-approle \
    token_policies="dbit" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=720h \
    secret_id_num_uses=0

# Create healthcare AppRole
vault write auth/approle/role/healthcare-approle \
    token_policies="healthcare" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=720h \
    secret_id_num_uses=0
```

### 4. Get RoleIDs and Generate SecretIDs

```bash
# Get dbit RoleID
vault read auth/approle/role/dbit-approle/role-id

# Get healthcare RoleID
vault read auth/approle/role/healthcare-approle/role-id

# Generate dbit SecretID
vault write -f auth/approle/role/dbit-approle/secret-id

# Generate healthcare SecretID
vault write -f auth/approle/role/healthcare-approle/secret-id
```

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

1. Add a credential for dbit:
   - Go to **Jenkins Dashboard > Manage Jenkins > Credentials > System > Global credentials**
   - Click **Add Credentials**
   - Select **Vault App Role Credential** from the dropdown
   - Enter:
     - **ID**: `dbit-approle-credentials`
     - **Description**: "Vault AppRole for dbit application"
     - **Role ID**: Enter the dbit Role ID
     - **Secret ID**: Enter the dbit Secret ID
   - Click **OK**

2. Add a credential for healthcare:
   - Go to **Jenkins Dashboard > Manage Jenkins > Credentials > System > Global credentials**
   - Click **Add Credentials**
   - Select **Vault App Role Credential** from the dropdown
   - Enter:
     - **ID**: `healthcare-approle-credentials`
     - **Description**: "Vault AppRole for healthcare application"
     - **Role ID**: Enter the healthcare Role ID
     - **Secret ID**: Enter the healthcare Secret ID
   - Click **OK**

## Using Vault Secrets in Jenkinsfiles

### Example for dbit Application

```groovy
pipeline {
    agent { label 'aws-poc-build' }
    options { timestamps() }
    
    stages {
        stage('Fetch dbit Secrets') {
            steps {
                withVault(
                    configuration: [
                        vaultCredentialId: 'dbit-approle-credentials',
                        engineVersion: 2 // This specifies KV v2
                    ],
                    vaultSecrets: [
                        [path: 'secrets/data/dbit', secretValues: [
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

### Example for Healthcare Application

```groovy
pipeline {
    agent { label 'aws-poc-build' }
    options { timestamps() }
    
    stages {
        stage('Fetch Healthcare Secrets') {
            steps {
                withVault(
                    configuration: [
                        vaultCredentialId: 'healthcare-approle-credentials',
                        engineVersion: 2
                    ],
                    vaultSecrets: [
                        [path: 'secrets/data/healthcare', secretValues: [
                            [envVar: 'API_ENDPOINT', vaultKey: 'api_endpoint'],
                            [envVar: 'API_KEY', vaultKey: 'api_key'],
                            [envVar: 'DB_PASSWORD', vaultKey: 'db_password']
                        ]]
                    ]
                ) {
                    // Use healthcare secrets securely
                    sh 'echo "Connecting to healthcare API..."'
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
    agent { label 'aws-poc-build' }
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
                            path: 'secrets/data/dbit',
                            credentialsId: 'dbit-approle-credentials', 
                            secretValues: [
                                [envVar: 'DBIT_DB_PASSWORD', vaultKey: 'password']
                            ]
                        ],
                        [
                            path: 'secrets/data/healthcare',
                            credentialsId: 'healthcare-approle-credentials', 
                            secretValues: [
                                [envVar: 'HC_API_KEY', vaultKey: 'api_key']
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

2. **Monitoring and Alerting**:
   - Track SecretID expiration dates across all applications
   - Set up alerts for upcoming expirations
   - Monitor rotation failures and implement automated retries

3. **Overlapping Validity Periods**:
   - When rotating SecretIDs, implement a grace period where both old and new are valid
   - This prevents disruption if some components still use the old SecretID

4. **Documentation and Audit**:
   - Maintain clear documentation of rotation policies for each application tier
   - Keep audit logs of all rotation activities
   - Regularly review rotation policies as part of security governance

### Long TTLs vs. Rotation

While long TTLs (like 1+ years) are operationally simpler, we recommend a balanced approach where:

1. You implement automated rotation as a security best practice
2. You use longer TTLs (6-12 months) as a fallback to prevent unexpected expiration
3. You apply more frequent rotation to your highest-risk applications

With proper automation, the operational overhead of rotation can be minimized while still maintaining good security hygiene.
