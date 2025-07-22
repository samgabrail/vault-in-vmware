# AWS KMS Module

## Required variables

* `kms_key_deletion_window` - Duration in days after which the key is deleted after destruction of the resource (must be between 7 and 30 days)
* `resource_name_prefix` - Resource name prefix used for tagging and naming AWS resources

## Example usage

```hcl
module "kms" {
  source = "./modules/kms"

  kms_key_deletion_window   = var.kms_key_deletion_window
  resource_name_prefix      = var.resource_name_prefix
}
```


## Setting AWS KMS Credentials with systemd-managed Vault
When Vault is managed by systemd, you have several secure options for setting environment variables:

### Option 1: Using Environment directive in systemd service file (not recommended, use it if other methods don't work)

You can modify your Vault systemd service file (typically `/etc/systemd/system/vault.service`) to include environment variables:

```ini
[Unit]
Description=HashiCorp Vault
After=network.target

[Service]
Type=simple
User=vault
Group=vault
ExecStart=/usr/bin/vault server -config=/etc/vault/config.hcl
Restart=on-failure

# Set environment variables for AWS KMS credentials
Environment="AWS_ACCESS_KEY_ID=your_access_key"
Environment="AWS_SECRET_ACCESS_KEY=your_secret_key" 
Environment="AWS_REGION=us-east-2"

[Install]
WantedBy=multi-user.target
```

### Option 2: Using EnvironmentFile (more secure but option 3 is better)

A better approach is to place the environment variables in a separate file with restricted permissions:

1. Create an environment file:

```bash
sudo touch /etc/vault/aws-credentials.env
sudo chown vault:vault /etc/vault/aws-credentials.env
sudo chmod 600 /etc/vault/aws-credentials.env
```

2. Add your credentials to this file:

```
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=us-east-2
```

3. Reference this file in your systemd service:

```ini
[Service]
...
EnvironmentFile=/etc/vault/aws-credentials.env
...
```

### Option 3: Using systemd credentials with a wrapper script (Recommended)

Ubuntu 22.04 comes with systemd version 249, which fully supports the `systemd-creds` feature. This is a more secure method than plain environment variables since it encrypts sensitive information. Here's how to implement it step by step:

#### Step 1: Encrypt Your AWS Credentials

First, you'll use the `systemd-creds` command to encrypt your AWS credentials:

```bash
# Create the credentials directory
sudo mkdir -p /etc/vault/credentials

# Create encrypted credential for AWS access key
echo "YOUR_ACCESS_KEY" | sudo systemd-creds encrypt --name=aws-access-key - /etc/vault/credentials/aws-access-key.cred

# Create encrypted credential for AWS secret key
echo "YOUR_SECRET_KEY" | sudo systemd-creds encrypt --name=aws-secret-key - /etc/vault/credentials/aws-secret-key.cred
```

#### Step 2: Create a Wrapper Script

Create a wrapper script that reads the credentials and exports them:

```bash
sudo nano /usr/local/bin/vault-with-creds.sh
```

Add the following content:

```bash
#!/bin/bash
# Read the credentials from systemd credential files
export AWS_ACCESS_KEY_ID=$(cat "${CREDENTIALS_DIRECTORY}/aws-access-key")
export AWS_SECRET_ACCESS_KEY=$(cat "${CREDENTIALS_DIRECTORY}/aws-secret-key")

# Start vault with the environment variables set (using your actual config path)
exec /usr/bin/vault server -config=/opt/vault/config/config.hcl
```

Make it executable:

```bash
sudo chmod +x /usr/local/bin/vault-with-creds.sh
```

#### Step 3: Update Your Vault systemd Service File

Edit your Vault service file (typically at `/etc/systemd/system/vault.service`):

```bash
sudo nano /etc/systemd/system/vault.service
```

Update the service file to use LoadCredentialEncrypted and the wrapper script:

```ini
[Unit]
Description=HashiCorp Vault
After=network.target

[Service]
User=vault
Group=vault
LoadCredentialEncrypted=aws-access-key:/etc/vault/credentials/aws-access-key.cred
LoadCredentialEncrypted=aws-secret-key:/etc/vault/credentials/aws-secret-key.cred
ExecStart=/usr/local/bin/vault-with-creds.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

#### Step 4: Apply the Changes

Reload systemd and restart Vault:

```bash
sudo systemctl daemon-reload
sudo systemctl restart vault
sudo systemctl status vault
```

#### Step 5: Modify Vault Configuration

Update your Vault configuration to use the AWS KMS seal without explicitly specifying credentials, since they'll be provided via environment variables:

```go
seal "awskms" {
  kms_key_id = "your-kms-key-id"
  region     = "your-region"
}
```

#### How This Works

1. The credentials are encrypted at rest using the `systemd-creds` tool
2. When the Vault service starts, systemd decrypts the credentials and makes them available to the wrapper script via the `CREDENTIALS_DIRECTORY` environment variable
3. The wrapper script reads the decrypted credentials and exports them as environment variables
4. The AWS SDK in Vault picks up these environment variables automatically

#### Benefits

- Credentials are encrypted at rest on disk
- Credentials aren't visible in `ps` or process listings  
- You can rotate credentials by updating the encrypted files without changing the service file
- Improved security compared to plain text environment files
- The wrapper script approach ensures proper credential handling

This approach provides a significant security improvement over storing plain text credentials in configuration files or environment files while still being relatively easy to manage.

### General Comments:
After making any changes to systemd service files, remember to reload systemd and restart the Vault service:

```bash
sudo systemctl daemon-reload
sudo systemctl restart vault
```