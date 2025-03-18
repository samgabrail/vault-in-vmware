module "vpc" {
  source                   = "terraform-aws-modules/vpc/aws"
  version                  = "3.0.0"
  name                     = "${var.resource_name_prefix}-vault"
  cidr                     = var.vpc_cidr
  azs                      = var.azs
  enable_nat_gateway       = true
  one_nat_gateway_per_az   = true
  private_subnets          = var.private_subnet_cidrs
  public_subnets           = var.public_subnet_cidrs
  enable_dns_hostnames     = true
  enable_dns_support       = true
  enable_dhcp_options      = true
  dhcp_options_domain_name = var.domain
  dhcp_options_tags        = var.common_tags

  tags = var.common_tags
}