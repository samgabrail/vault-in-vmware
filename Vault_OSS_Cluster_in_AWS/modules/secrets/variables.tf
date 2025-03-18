variable "enable_private_ca" {
  type        = bool
  description = "If set to true, it will create a root and subordinate CA to create a cert for the LB to be used with ACM. ACM will auto-renew this cert so you don't need to worry about renewals. If set to false, which is default, a cert is created by Terraform and uploaded to ACM. This cert is not renewed by ACM, you will need to manage the renewal on your own."
}

variable "kms_key_id" {
  type        = string
  description = "Specifies the ARN or ID of the AWS KMS customer master key (CMK) to be used to encrypt the secret values in the versions stored in this secret. If you don't specify this value, then Secrets Manager defaults to using the AWS account's default CMK (the one named aws/secretsmanager"
  default     = null
}

variable "recovery_window" {
  type        = number
  description = "Specifies the number of days that AWS Secrets Manager waits before it can delete the secret"
  default     = 0
}

variable "resource_name_prefix" {
  type        = string
  description = "Prefix for resource names (e.g. \"prod\")"
}

# variable related to TLS cert generation
variable "shared_san" {
  type        = string
  description = "This is a shared server name that the certs for all Vault nodes contain. This is the same value you will supply as input to the Vault installation module for the leader_tls_servername variable."
  default     = "vault.server.com"
}

variable "common_tags" {
  type        = map(string)
  description = "Tags for secrets manager secret"
}

variable "validity_period_hours" {
  type        = number
  description = "how many hours till the cert expires for the vault server certs"
  default     = 43830 # 5 years to match the LB cert 
}

variable "lb_fqdn" {
  type        = string
  description = "Shared server name that the certs for all Vault nodes contain"
}

variable "domain" {
  type        = string
  description = "Shared server name that the certs for all Vault nodes contain"
}