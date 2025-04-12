resource "aws_acm_certificate" "vault" {
  count             = var.enable_private_ca ? 0 : 1
  private_key       = tls_private_key.server.private_key_pem
  certificate_body  = tls_locally_signed_cert.server.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem
}
