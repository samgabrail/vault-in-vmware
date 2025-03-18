output "bastion_private_key" {
  value     = module.secrets.bastion_private_key
  sensitive = true
}

output "subordinate_ca_arn" {
  description = "The ARN of the Subordinate CA"
  value       = module.cas_certs_route53.*.subordinate_ca_arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.aws-vpc.vpc_id
}

output "private_subnet_names" {
  description = "Private subnet names"
  value       = module.aws-vpc.private_subnet_names.*
}
