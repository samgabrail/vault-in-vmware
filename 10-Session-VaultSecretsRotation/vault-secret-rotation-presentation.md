# Vault for Secret Rotation
**Presenter:** Sam Gabrail  
**Session:** HashiCorp Vault - Secret Rotation Deep Dive

[Image: HashiCorp Vault logo]

> Welcome to our deep dive into HashiCorp Vault's secret rotation capabilities. Today we'll explore how Vault can transform your organization's approach to credential management through automated rotation.

---

## Agenda

- **What is Secret Rotation and Why It Matters**
- **Types of Rotation: Dynamic vs Static**
- **Supported Dynamic Secrets Engines**
- **Implementation Steps for Static Rotation**
- **Pilot Application Implementation**
- **Live Demo**
- **Q&A**

> 32 minutes of presentation, 8 minutes demo, 20 minutes Q&A

---

## What is Secret Rotation?

### Definition
Secret rotation is the **automated process** of regularly updating and replacing credentials, passwords, API keys, and other sensitive data.

### Why It Matters
- **Reduces blast radius** of compromised credentials
- **Limits exposure time** - breached credentials have limited lifespan
- **Compliance requirements** - SOX, PCI DSS, HIPAA mandate rotation
- **Eliminates manual processes** - no more password spreadsheets
- **Prevents credential sprawl** - centralized management

### The Problem We're Solving
- Static credentials live forever until manually changed
- Manual rotation is error-prone and often skipped
- Compromised credentials can be used indefinitely
- No audit trail of who accessed what and when

---

## Types of Rotation in Vault

### Dynamic Secrets (Just-in-Time)
- **Created on-demand** when applications request access
- **Short-lived** with automatic expiration (minutes to hours)
- **No rotation needed** - they're ephemeral by design
- **Automatic cleanup** when TTL expires
- **Perfect forward secrecy** - each session is unique

### Static Secrets with Automated Rotation
- **Long-lived credentials** that exist in external systems
- **Periodic rotation** based on policies (hourly, daily, weekly)
- **Coordinated updates** between Vault and target systems
- **Version history** maintained for rollback
- **Best for** legacy applications that can't be modified

[Image: Comparison diagram showing dynamic vs static secret lifecycles]

---

## Dynamic Secrets - Supported Engines

### Databases (16+ Types)
**Relational:** PostgreSQL, MySQL/MariaDB, MSSQL, Oracle, IBM Db2, Redshift, Snowflake  
**NoSQL:** MongoDB, MongoDB Atlas, Cassandra, Couchbase, HanaDB  
**Time-Series:** InfluxDB  
**Search:** Elasticsearch  
**Cache:** Redis, Redis ElastiCache  
**Custom:** Plugin interface for proprietary databases

### Cloud Providers
**AWS:** IAM users, STS credentials, access keys  
**Azure:** Service principals, managed identities  
**Google Cloud:** Service accounts, access tokens  
**AliCloud:** RAM users and policies  
**Oracle Cloud Infrastructure:** Dynamic principals

---

## More Dynamic Secrets Engines

### Infrastructure & Platform Services
**Kubernetes:** Service accounts, RBAC roles  
**Nomad:** ACL tokens  
**Consul:** ACL tokens  
**HCP Terraform:** API tokens  
**RabbitMQ:** User credentials  
**SSH:** Certificate-based access, OTP

### Identity & Access
**Active Directory:** Dynamic service account passwords  
**LDAP:** Dynamic user credential generation  
**OpenLDAP:** Dynamic credential management

### Certificates & Encryption
**PKI:** X.509 certificates with custom TTLs  
**Transit:** Encryption as a service  
**Transform:** Format-preserving encryption

> Each engine has specific configuration requirements and supports different credential types

---

## Static Secret Rotation Process

### Flow for Static Rotation
**Option A: Vault-Generated Password**
1. **Vault generates new password** (using password policies)
2. **User retrieves password** from Vault
3. **User updates target system** with new credential
4. **Applications retrieve** updated credential from Vault

**Option B: Externally Generated**
1. **User generates credential** in their system
2. **User updates target system** with new credential
3. **User stores credential** in Vault
4. **Applications retrieve** from Vault

### Key Difference from Dynamic
- **Manual update** of target system required
- **User-initiated** rotation process
- **Vault can generate** passwords with policies
- **Useful for** third-party APIs, legacy systems

---

## Vault Password Generation

### Create Password Policy
```bash
vault write sys/policies/password/my-policy policy=-<<EOF
length=20
rule "charset" {
  charset = "abcdefghijklmnopqrstuvwxyz"
  min-chars = 1
}
rule "charset" {
  charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  min-chars = 1
}
rule "charset" {
  charset = "0123456789"
  min-chars = 1
}
EOF
```

### Generate Password
```bash
vault read -field password sys/policies/password/my-policy/generate
```

### Benefits
- Consistent complexity requirements
- Centralized password policies
- No external password generators needed

---

## Pilot Application Strategy

### Selecting Your Pilot
**Good Candidates:**
- Non-critical application with database access
- Application with existing credential management pain
- Team willing to be early adopters
- Clear success metrics defined

**Start Small:**
- Single application, single database
- Dynamic credentials for new connections
- Static rotation for existing service accounts
- Gradual rollout to other components

### Success Criteria
- Zero credential-related outages
- Reduced time to rotate credentials
- Complete audit trail of access
- Improved security posture metrics

---

## Demo Scenario Overview

### What We'll Demonstrate (8 minutes)

**Part 1: Static MySQL Secret Rotation**
- Vault-generated password using policies
- Complete MySQL password rotation workflow
- Manual coordination between systems
- Version history and rollback capabilities

**Part 2: Dynamic MySQL Credentials (Same Database)**
- On-demand credential generation
- Automatic cleanup after TTL expiration
- Direct comparison with static approach
- Perfect forward secrecy demonstration

> Live demo environment: Vault Dev Server + MySQL Container (same database for both parts)
