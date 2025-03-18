resource "tls_private_key" "bastion_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "${var.resource_name_prefix}-bastion"
  public_key = tls_private_key.bastion_key.public_key_openssh
}