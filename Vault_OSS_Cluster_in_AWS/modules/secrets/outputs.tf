output "lb_certificate_arn" {
  value       = var.enable_private_ca ? "" : aws_acm_certificate.vault[0].arn
  description = "ARN of ACM cert to use with Vault LB listener"
}

output "leader_tls_servername" {
  description = "Shared SAN that will be given to the Vault nodes configuration for use as leader_tls_servername"
  value       = var.shared_san
}

output "secrets_manager_arn" {
  description = "ARN of secrets_manager secret"
  value       = aws_secretsmanager_secret.tls.arn
}

output "bastion_private_key" {
  value     = tls_private_key.bastion_key.private_key_pem
  sensitive = true
}

output "bastion_public_key" {
  value = tls_private_key.bastion_key.public_key_openssh
}

output "bastion_key_name" {
  value = aws_key_pair.bastion_key.key_name
}