variable "region" {
  type        = string
  description = "AWS Region"
  default     = "us-east-1"
}

variable "enable_private_ca" {
  type        = bool
  description = "If set to true, it will create a root and subordinate CA to create a cert for the LB to be used with ACM. ACM will auto-renew this cert so you don't need to worry about renewals. If set to false, which is default, a cert is created by Terraform and uploaded to ACM. This cert is not renewed by ACM, you will need to manage the renewal on your own."
  default     = false
}

variable "resource_name_prefix" {
  type        = string
  description = "prefix for tagging/naming AWS resources"
  default     = "vault-dev"
}

variable "lb_fqdn" {
  type        = string
  description = "Shared server name that the certs for all Vault nodes contain"
  default     = "vault-dev.vault202.local"
}

variable "domain" {
  type        = string
  description = "Shared server name that the certs for all Vault nodes contain"
  default     = "vault202.local"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "user_supplied_ami_id" {
  type        = string
  description = "AMI to be used, default will use Ubuntu 22.04"
  default     = "ami-0fd2c44049dd805b8"
}

variable "node_count" {
  type        = string
  description = "Number of Vault nodes"
  default     = "3"
}

variable "bastion_node_count" {
  type        = number
  description = "Number of bastion vms to deploy in ASG"
  default     = 1
}

variable "monitoring_node_count" {
  type        = number
  description = "Number of monitoring vms to deploy in ASG"
  default     = 1
}

variable "vault_version" {
  type        = string
  description = "Vault version"
  default     = "1.13.2"
}

variable "lb_certificate_arn" {
  type        = string
  description = "The cert ARN to be used on the Vault LB listener"
  default     = ""
}

variable "vpc_id" {
  type        = string
  description = "The vpc id to deploy vault in"
  default     = ""
}

variable "vpc_cidr" {
  type        = string
  description = "The vpc CIDR to deploy vault in"
  default     = "10.0.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "A list of Availability Zones"
  default     = ["us-east-1d", "us-east-1e", "us-east-1f"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "The public subnet CIDRs to be used for deploying a bastion host"
  default     = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "The private subnet CIDRs to be used for deploying the Vault servers in"
  default     = ["10.0.0.0/19", "10.0.32.0/19", "10.0.64.0/19"]
}

variable "allowed_inbound_cidrs_lb" {
  type        = list(string)
  description = "CIDR allowed to access the LB"
  default     = ["0.0.0.0/0"]
}

variable "validity_period_hours" {
  type        = number
  description = "how many hours till the cert expires for the vault server certs"
  default     = 720
}

variable "DATADOG_API_KEY" {
  type        = string
  description = "API key for the datadog agent to talk to the SaaS backend"
  default     = ""
}

variable "env" {
  type        = string
  description = "The Vault environment e.g. dev or prod"
  default     = "dev"
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags across multiple AWS resources"
  default = {
    "env"              = "dev"
    "managed_by"       = "Terraform"
    "PrometheusScrape" = "Enabled"
  }
}

variable "allowed_inbound_cidrs_ssh" {
  type        = list(string)
  description = "(Optional) List of CIDR blocks to permit for SSH to Vault nodes"
  default     = null
}

variable "additional_lb_target_groups" {
  type        = list(string)
  description = "(Optional) List of load balancer target groups to associate with the Vault cluster. These target groups are _in addition_ to the LB target group this module provisions by default."
  default     = []
}

variable "kms_key_deletion_window" {
  type        = number
  default     = 7
  description = "Duration in days after which the key is deleted after destruction of the resource (must be between 7 and 30 days)."
}

variable "lb_deregistration_delay" {
  type        = string
  description = "Amount time, in seconds, for Vault LB target group to wait before changing the state of a deregistering target from draining to unused."
  default     = 300
}

variable "lb_health_check_path" {
  type        = string
  description = "The endpoint to check for Vault's health status."
  default     = "/v1/sys/health"
}

variable "lb_type" {
  description = "The type of load balancer to provision; network or application."
  type        = string
  default     = "application"

  validation {
    condition     = contains(["application", "network"], var.lb_type)
    error_message = "The variable lb_type must be one of: application, network."
  }
}


variable "permissions_boundary" {
  description = "(Optional) IAM Managed Policy to serve as permissions boundary for created IAM Roles"
  type        = string
  default     = null
}

variable "secrets_manager_arn" {
  type        = string
  description = "Secrets manager ARN where TLS cert info is stored"
  default     = ""
}

variable "ssl_policy" {
  type        = string
  default     = "ELBSecurityPolicy-TLS-1-2-2017-01"
  description = "SSL policy to use on LB listener"
}


variable "user_supplied_iam_role_name" {
  type        = string
  description = "(Optional) User-provided IAM role name. This will be used for the instance profile provided to the AWS launch configuration. The minimum permissions must match the defaults generated by the IAM submodule for cloud auto-join and auto-unseal."
  default     = null
}

variable "user_supplied_kms_key_arn" {
  type        = string
  description = "(Optional) User-provided KMS key ARN. Providing this will disable the KMS submodule from generating a KMS key used for Vault auto-unseal"
  default     = null
}

variable "private_ip_monitoring" {
  description = "The private IP address of the monitoring EC2 instance"
  type        = string
  default     = "10.0.64.10"
}

# variable "VAULT_LICENSE" {
#   type        = string
#   description = "The Vault license"
# }
