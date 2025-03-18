output "lb_certificate_arn" {
  description = "ARN of ACM cert to use with Vault LB listener"
  value       = aws_acm_certificate.vault.arn
}

output "subordinate_ca_arn" {
  description = "The ARN of the Subordinate CA"
  value       = aws_acmpca_certificate_authority.subordinate.arn
}
