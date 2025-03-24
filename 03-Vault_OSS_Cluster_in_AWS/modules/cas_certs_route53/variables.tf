variable "vpc_id" {
  type        = string
  description = "VPC ID where Vault will be deployed"
}

variable "vault_lb_dns_name" {
  type        = string
  description = "The LB DNS Name to use it for route 53 record"
}

variable "vault_lb_zone_id" {
  type        = string
  description = "The LB zone id to use it for route 53 record"
}

variable "domain" {
  type        = string
  description = "Shared server name that the certs for all Vault nodes contain"
}

variable "lb_fqdn" {
  type        = string
  description = "Shared server name that the certs for all Vault nodes contain"
}

variable "common_tags" {
  type        = map(string)
  description = "(Optional) Map of common tags for all taggable AWS resources."
  default     = {}
}