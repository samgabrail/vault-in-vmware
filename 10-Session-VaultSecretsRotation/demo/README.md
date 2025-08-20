# HashiCorp Vault Secret Rotation Demo

This demo accompanies the "Vault for Secret Rotation" presentation and demonstrates two key approaches to secret management with HashiCorp Vault using the **same MySQL database** to show the clear contrast between approaches:

1. **Static MySQL Secret Rotation** - Traditional rotation with Vault-generated passwords
2. **Dynamic MySQL Credentials** - Just-in-time credential generation (no rotation needed)

## 🎯 Demo Flow & Purpose

The demo is designed to show a **direct comparison** using the same MySQL database:
- **Part 1** demonstrates the traditional approach of rotating static database passwords
- **Part 2** shows how dynamic secrets eliminate rotation entirely

This progression clearly illustrates why dynamic secrets represent the evolution beyond traditional rotation.

## Prerequisites

### Required Software
- **HashiCorp Vault** - Download from [vaultproject.io](https://www.vaultproject.io/downloads)
- **jq** - JSON processor for parsing Vault responses
- **Docker** - Required for MySQL database (both parts use same instance)

### Installation Commands

**macOS (Homebrew):**
```bash
brew install vault jq docker
```

**Ubuntu/Debian:**
```bash
# Vault
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install vault

# jq and Docker
sudo apt-get install jq docker.io
```

**CentOS/RHEL:**
```bash
# Vault
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install vault

# jq and Docker
sudo yum install jq docker
sudo systemctl start docker
```

## Quick Start

### 1. Start Vault Dev Server
```bash
vault server -dev -dev-root-token-id=myroot
```

### 2. Set Environment Variables
In a new terminal:
```bash
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='myroot'
```

### 3. Run Complete Demo
```bash
cd demo
chmod +x master-demo.sh
./master-demo.sh
```

## Demo Structure

```
demo/
├── master-demo.sh                    # Main orchestration script
├── README.md                         # This file
├── part1-static-mysql/              # Static MySQL rotation demo
│   ├── setup.sh                     # Configure KV engine and password policies
│   ├── mysql-setup.sh               # Start MySQL container (shared with Part 2)
│   ├── rotate-mysql-password.sh     # Complete MySQL rotation workflow
│   └── demo.sh                      # Orchestrate static rotation demonstration
└── part2-dynamic-mysql/             # Dynamic MySQL credentials demo
    ├── setup.sh                     # Configure database secrets engine
    └── demo.sh                      # Demonstrate dynamic credential generation
```

## Individual Demo Parts

### Part 1: Static MySQL Secret Rotation

**What it demonstrates:**
- Vault-generated passwords using configurable policies
- Complete static rotation workflow for MySQL service accounts
- Manual coordination between Vault, database, and applications
- Version history and rollback capabilities
- The traditional but improved approach to credential rotation

**The Six-Step Static Rotation Flow:**
1. **Vault generates password** using configured policies
2. **User retrieves password** from Vault  
3. **User updates MySQL database** with new password
4. **User updates application configuration**
5. **User stores credential metadata** in Vault
6. **Applications retrieve** updated credential from Vault

**Setup:**
```bash
cd part1-static-mysql
./mysql-setup.sh      # Start MySQL container (shared with Part 2)
./setup.sh            # Configure Vault KV engine and password policy
./demo.sh             # Run complete demonstration
```

**Manual Rotation:**
```bash
# Rotate MySQL service account password
./rotate-mysql-password.sh
```

**Password Policy:**
```hcl
length=24
rule "charset" {
  charset = "abcdefghijklmnopqrstuvwxyz"
  min-chars = 2
}
rule "charset" {
  charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  min-chars = 2
}
rule "charset" {
  charset = "0123456789"  
  min-chars = 2
}
rule "charset" {
  charset = "@#%"
  min-chars = 1
}
```

**Key Commands:**
```bash
# Generate password using policy
vault read -field=password sys/policies/password/mysql-static-policy/generate

# Store rotated credential with metadata
vault kv put static-secrets/mysql/service-accounts/app-service-user \
    username="app-service-user" \
    password="$NEW_PASSWORD" \
    rotation_date="$(date -Iseconds)"

# Retrieve credential
vault kv get static-secrets/mysql/service-accounts/app-service-user
```

### Part 2: Dynamic MySQL Credentials

**What it demonstrates:**
- On-demand credential generation with unique usernames
- Automatic cleanup after TTL expiration  
- No standing credentials in the database
- Perfect forward secrecy (each request = unique credentials)
- The modern approach that eliminates rotation entirely

**Key Difference from Part 1:**
- **No rotation needed** - credentials are ephemeral by design
- **Unique per request** - each application request gets different credentials
- **Automatic cleanup** - MySQL users are removed when TTL expires
- **Zero operational overhead** - no manual processes required

**Setup:**
```bash
cd part2-dynamic-mysql
./setup.sh            # Configure database secrets engine (uses existing MySQL)
./demo.sh             # Run complete demonstration with comparison
```

**Dynamic Role Created:**
- `dynamic-app` (10s TTL) - Full CRUD operations for quick demo

**Key Commands:**
```bash
# Generate dynamic credentials (unique each time)
vault read database/creds/dynamic-app

# Each request creates a new MySQL user like: v-token-dynamic-a-xyz123
```

**Direct Comparison:**
The demo shows the same MySQL database with:
- Static user: `app-service-user` (permanent, needs rotation)
- Dynamic users: `v-token-*` (temporary, auto-expire)

## Running Individual Components

### Run Specific Parts
```bash
./master-demo.sh part1    # Static MySQL rotation only
./master-demo.sh part2    # Dynamic MySQL credentials only
```

### Cleanup
```bash
./master-demo.sh cleanup
```

## Key Takeaways

### Static vs Dynamic Comparison

**Static Rotation (Part 1):**
- ✅ Significant improvement over never rotating
- ✅ Works with legacy applications that can't be modified
- ✅ Vault generates strong passwords consistently  
- ⚠️ Still requires manual coordination and processes
- ⚠️ Credentials exist for extended periods
- ⚠️ Operational overhead for rotation scheduling

**Dynamic Secrets (Part 2):**
- ✅ Ultimate security posture (no rotation needed)
- ✅ Zero operational rotation overhead
- ✅ Perfect forward secrecy (unique per request)
- ✅ Automatic cleanup prevents credential sprawl
- ⚠️ Requires application integration with Vault
- ⚠️ Not suitable for all legacy systems

### Implementation Strategy

1. **Start with a pilot** - Choose low-risk, high-value application
2. **Dynamic for new apps** - Build with Vault integration from start  
3. **Static rotation for legacy** - Gradual improvement of existing systems
4. **Expand gradually** - Learn and iterate across organization
5. **Migrate when possible** - Move from static to dynamic over time

### The Clear Winner

**Dynamic secrets represent the evolution beyond rotation:**
- Instead of rotating credentials, eliminate long-lived credentials entirely
- Each database connection uses unique, short-lived credentials  
- Automatic cleanup prevents the accumulation of unused accounts
- Perfect security with minimal operational overhead

## Troubleshooting

### Common Issues

**Vault not accessible:**
```bash
# Check if Vault is running
vault status

# Start in dev mode if needed
vault server -dev -dev-root-token-id=myroot

# Set environment variables
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='myroot'
```

**MySQL connection failed:**
```bash
# Check if Docker is running and MySQL container exists
docker ps

# Restart MySQL container if needed
docker stop vault-mysql-demo
docker rm vault-mysql-demo
cd part1-static-mysql && ./mysql-setup.sh
```

**Permission denied on scripts:**
```bash
# Make all scripts executable
find . -name "*.sh" -exec chmod +x {} \;
```

### Logs and Debugging

**MySQL user inspection:**
```bash
# View all MySQL users (static + dynamic)
docker exec vault-mysql-demo mysql -u root -prootpassword -e "
SELECT User, Host, 
CASE 
  WHEN User = 'app-service-user' THEN 'Static'
  WHEN User LIKE 'v-token-%' THEN 'Dynamic'
  ELSE 'System'
END as Type
FROM mysql.user 
WHERE User NOT IN ('mysql.session', 'mysql.sys', 'mysql.infoschema');"
```

## Production Considerations

### Security
- Use proper authentication methods (not root token)
- Enable TLS encryption for all communications
- Implement proper access policies with least privilege
- Regular security reviews of Vault policies

### High Availability  
- Multi-node Vault cluster for redundancy
- Integrated storage (Raft) or external storage backend
- Load balancer health checks and failover
- Comprehensive backup and recovery procedures

### Monitoring
- Multiple audit backends for redundancy
- Integration with SIEM platforms (Splunk, ELK stack)
- Automated alerting on failures and anomalies
- Performance metrics collection and analysis

### Operational
- Automated log rotation and archival
- Infrastructure as Code for Vault configuration
- Disaster recovery testing procedures
- Staff training and operational documentation

## Resources

- **HashiCorp Learn:** [learn.hashicorp.com/vault](https://learn.hashicorp.com/vault)
- **Vault Documentation:** [vaultproject.io/docs](https://www.vaultproject.io/docs)
- **API Reference:** [vaultproject.io/api-docs](https://www.vaultproject.io/api-docs)
- **Community Forum:** [discuss.hashicorp.com](https://discuss.hashicorp.com)

## Support

For questions about this demo or Vault implementation:
- Review the presentation slides
- Check HashiCorp documentation  
- Post questions on HashiCorp Discuss forum
- Contact your HashiCorp representative