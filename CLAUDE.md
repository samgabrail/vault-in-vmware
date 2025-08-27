# Vault in VMware - Project Context

## Overview
This repository contains a comprehensive HashiCorp Vault deployment and training project specifically designed for VMware environments. It includes multiple sessions/modules covering various aspects of Vault configuration, management, and integration.

## Repository Structure

### Core Sessions/Modules

1. **01-nomad-packer-terraform-vsphere** - Infrastructure automation tools for VMware vSphere
2. **02-terraform-vsphere-module** - Terraform modules for vSphere deployments
3. **03-Vault_OSS_Cluster_in_AWS** - Vault OSS cluster setup in AWS environment
4. **04-terraform-vault-configuration** - Terraform-based Vault configuration including policies:
   - Admin policy
   - Developer policy
   - Jenkins policy and pipeline policy
   - ADO (Azure DevOps) policy
   - Operation policy
   - Webblog policy

5. **05-Session4-Policies-and-Auth** - Vault policies and authentication methods
6. **06-Session5-SecretZero** - Secret Zero implementation patterns
7. **07-Session6-VaultAgent** - Vault Agent configuration and usage
8. **08-Session7-DistributedVaultAgentModel** - Distributed Vault Agent deployment models
9. **09-Session8and9-UpdatingScripts** - Script automation for different personas:
   - System administrator setup and operations
   - Vault administrator configuration
   - Raft snapshot and restore operations
   - Audit log configuration
   - Demo application secret management

10. **10-Session-VaultSecretsRotation** - Secret rotation strategies and demonstrations
11. **11-Session-AD-Vault** - Active Directory integration with Vault (newly created)

## Key Technologies
- **HashiCorp Vault** - Secret management and data protection
- **Terraform** - Infrastructure as Code for Vault configuration
- **VMware vSphere** - Target virtualization platform
- **Nomad** - Orchestration (session 1)
- **Packer** - Image building (session 1)
- **Raft** - Vault's integrated storage backend

## Vault Maintenance Guidelines
The repository includes upgrade recommendations:
- **Critical Security Updates**: Immediate patching (0-7 days)
- **Regular Updates**: Quarterly schedule (every 3-4 months)
- Monitoring for CVEs and security advisories is essential
- HashiCorp supports current version + 2 previous versions for Enterprise

## Development Environment
- Contains `.devcontainer` configuration for containerized development
- Git repository with standard `.gitignore` configuration

## Recent Activity
- Active development on Vault secrets rotation mechanisms
- Recent removal of verbose output and testing documentation
- Addition of KMS third option support
- New session on Active Directory integration with Vault

## File Types Present
- Terraform configurations (`.tf`, `.hcl`)
- Shell scripts (`.sh`) for automation
- Policy files (`.hcl`)
- Documentation (`.md`)
- Configuration files (`.json`, `.yml`, `.yaml`)