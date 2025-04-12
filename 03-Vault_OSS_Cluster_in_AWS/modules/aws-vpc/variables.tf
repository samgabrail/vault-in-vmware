variable "azs" {
  description = "availability zones to use in AWS region"
  type        = list(string)
}

variable "common_tags" {
  type        = map(string)
  description = "Tags for VPC resources"
}

variable "resource_name_prefix" {
  description = "Prefix for resource names (e.g. \"prod\")"
  type        = string
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "domain" {
  type        = string
  description = "Shared server name that the certs for all Vault nodes contain"
}
