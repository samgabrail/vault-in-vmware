variable "allowed_inbound_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks to permit inbound traffic from to load balancer"
  default     = null
}

variable "allowed_inbound_cidrs_ssh" {
  type        = list(string)
  description = "List of CIDR blocks to give SSH access to Vault nodes"
  default     = null
}

variable "aws_iam_instance_profile" {
  type        = string
  description = "IAM instance profile name to use for Vault instances"
}

variable "common_tags" {
  type        = map(string)
  description = "(Optional) Map of common tags for all taggable AWS resources."
  default     = {}
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "monitoring_key_name" {
  type        = string
  description = "key pair to use for SSH access to instance"
  default     = null
}

variable "lb_type" {
  description = "The type of load balancer to provision: network or application."
  type        = string
}

variable "node_count" {
  type        = number
  description = "Number of Vault nodes to deploy in ASG"
  default     = 1
}

variable "monitoring_node_count" {
  type        = number
  description = "Number of monitoring vms to deploy in ASG"
  default     = 1
}

variable "resource_name_prefix" {
  type        = string
  description = "Resource name prefix used for tagging and naming AWS resources"
}

variable "userdata_monitoring_script" {
  type        = string
  description = "Userdata script for monitoring instance"
}

variable "user_supplied_ami_id" {
  type        = string
  description = "AMI ID to use with Vault instances"
  default     = null
}

variable "monitoring_subnets" {
  type        = list(string)
  description = "Public subnets IDs where the monitoring hosts will be deployed"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where Vault will be deployed"
}

variable "env" {
  type        = string
  description = "The Vault environment e.g. dev or prod"
}

variable "ingress_ports" {
  type        = map(number)
  description = "A map of ingress ports"
  default = {
    "ssh"           = 22
    "grafana"       = 3000
    "prometheus"    = 9090
    "promtail"      = 9080
    "node-exporter" = 9100
    "alert-manager" = 9094
    "cadvisor"      = 8080
    "loki"          = 3100
  }
}

variable "private_ip_monitoring" {
  description = "The private IP address of the monitoring EC2 instance"
  type        = string
}