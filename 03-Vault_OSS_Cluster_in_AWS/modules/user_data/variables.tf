

variable "aws_region" {
  type        = string
  description = "AWS region where Vault is being deployed"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS Key ARN used for Vault auto-unseal"
}

variable "leader_tls_servername" {
  type        = string
  description = "One of the shared DNS SAN used to create the certs use for mTLS"
}

variable "resource_name_prefix" {
  type        = string
  description = "Resource name prefix used for tagging and naming AWS resources"
}

variable "secrets_manager_arn" {
  type        = string
  description = "Secrets manager ARN where TLS cert info is stored"
}

variable "vault_version" {
  type        = string
  description = "Vault version"
}

variable "DATADOG_API_KEY" {
  type        = string
  description = "API key for the datadog agent to talk to the SaaS backend"
}

variable "env" {
  type        = string
  description = "The Vault environment e.g. dev or prod"
}

variable "lb_fqdn" {
  type        = string
  description = "The LB's FQDN"
}

variable "subordinate_ca_arn" {
  type        = string
  description = "The ARN of the Subordinate CA"
}

variable "private_ip_monitoring" {
  description = "The private IP address of the monitoring EC2 instance"
  type        = string
}

# variable "VAULT_LICENSE" {
#   type        = string
#   description = "The Vault license"
# }