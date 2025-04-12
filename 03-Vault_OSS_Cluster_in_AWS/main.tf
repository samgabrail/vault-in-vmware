terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.62.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_region" "current" {}

module "secrets" {
  source                = "./modules/secrets"
  resource_name_prefix  = var.resource_name_prefix
  shared_san            = var.lb_fqdn
  validity_period_hours = var.validity_period_hours
  common_tags           = var.common_tags
  domain                = var.domain
  lb_fqdn               = var.lb_fqdn
  enable_private_ca     = var.enable_private_ca
}

module "aws-vpc" {
  source               = "./modules/aws-vpc"
  resource_name_prefix = var.resource_name_prefix
  azs                  = var.azs
  common_tags          = var.common_tags
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  vpc_cidr             = var.vpc_cidr
  domain               = var.domain
}

module "iam" {
  source = "./modules/iam"

  aws_region                  = data.aws_region.current.name
  kms_key_arn                 = module.kms.kms_key_arn
  permissions_boundary        = var.permissions_boundary
  resource_name_prefix        = var.resource_name_prefix
  secrets_manager_arn         = module.secrets.secrets_manager_arn
  user_supplied_iam_role_name = var.user_supplied_iam_role_name
}

module "kms" {
  source = "./modules/kms"

  common_tags               = var.common_tags
  kms_key_deletion_window   = var.kms_key_deletion_window
  resource_name_prefix      = var.resource_name_prefix
  user_supplied_kms_key_arn = var.user_supplied_kms_key_arn
}

module "loadbalancer" {
  source = "./modules/load_balancer"

  allowed_inbound_cidrs   = var.allowed_inbound_cidrs_lb
  common_tags             = var.common_tags
  lb_certificate_arn      = var.enable_private_ca ? module.cas_certs_route53[0].lb_certificate_arn : module.secrets.lb_certificate_arn
  lb_deregistration_delay = var.lb_deregistration_delay
  lb_health_check_path    = var.lb_health_check_path
  lb_subnets              = module.aws-vpc.private_subnet_ids
  lb_type                 = var.lb_type
  resource_name_prefix    = var.resource_name_prefix
  ssl_policy              = var.ssl_policy
  vault_sg_id             = module.vm.vault_sg_id
  vpc_id                  = module.aws-vpc.vpc_id
}

module "cas_certs_route53" {
  count             = var.enable_private_ca ? 1 : 0
  source            = "./modules/cas_certs_route53"
  vpc_id            = module.aws-vpc.vpc_id
  vault_lb_dns_name = module.loadbalancer.vault_lb_dns_name
  vault_lb_zone_id  = module.loadbalancer.vault_lb_zone_id
  domain            = var.domain
  lb_fqdn           = var.lb_fqdn
  common_tags       = var.common_tags
}

module "route53" {
  count             = var.enable_private_ca ? 0 : 1
  source            = "./modules/route53"
  vpc_id            = module.aws-vpc.vpc_id
  domain            = var.domain
  lb_fqdn           = var.lb_fqdn
  vault_lb_dns_name = module.loadbalancer.vault_lb_dns_name
  vault_lb_zone_id  = module.loadbalancer.vault_lb_zone_id
}

module "user_data" {
  source                = "./modules/user_data"
  private_ip_monitoring = var.private_ip_monitoring
  aws_region            = data.aws_region.current.name
  kms_key_arn           = module.kms.kms_key_arn
  leader_tls_servername = module.secrets.leader_tls_servername
  resource_name_prefix  = var.resource_name_prefix
  secrets_manager_arn   = module.secrets.secrets_manager_arn
  vault_version         = var.vault_version
  DATADOG_API_KEY       = var.DATADOG_API_KEY
  env                   = var.env
  lb_fqdn               = var.lb_fqdn
  subordinate_ca_arn    = var.enable_private_ca ? module.cas_certs_route53[0].subordinate_ca_arn : ""
  # VAULT_LICENSE         = var.VAULT_LICENSE
}

locals {
  vault_target_group_arns = concat(
    [module.loadbalancer.vault_target_group_arn],
    var.additional_lb_target_groups,
  )
}

module "vm" {
  source = "./modules/vm"

  allowed_inbound_cidrs     = var.allowed_inbound_cidrs_lb
  allowed_inbound_cidrs_ssh = var.allowed_inbound_cidrs_ssh
  aws_iam_instance_profile  = module.iam.aws_iam_instance_profile
  common_tags               = var.common_tags
  instance_type             = var.instance_type
  lb_type                   = var.lb_type
  node_count                = var.node_count
  resource_name_prefix      = var.resource_name_prefix
  userdata_script           = module.user_data.vault_userdata_base64_encoded
  user_supplied_ami_id      = var.user_supplied_ami_id
  vault_lb_sg_id            = module.loadbalancer.vault_lb_sg_id
  vault_subnets             = module.aws-vpc.private_subnet_ids
  vault_target_group_arns   = local.vault_target_group_arns
  vpc_id                    = module.aws-vpc.vpc_id
  private_ip_monitoring     = var.private_ip_monitoring
  env                       = var.env
}

module "bastion" {
  source = "./modules/bastion"

  allowed_inbound_cidrs     = var.allowed_inbound_cidrs_lb
  allowed_inbound_cidrs_ssh = var.allowed_inbound_cidrs_ssh
  aws_iam_instance_profile  = module.iam.aws_iam_instance_profile
  common_tags               = var.common_tags
  instance_type             = var.instance_type
  bastion_key_name          = module.secrets.bastion_key_name
  lb_type                   = var.lb_type
  bastion_node_count        = var.bastion_node_count
  bastion_subnets           = module.aws-vpc.public_subnet_ids
  resource_name_prefix      = var.resource_name_prefix
  userdata_bastion_script   = module.user_data.bastion_userdata_base64_encoded
  user_supplied_ami_id      = var.user_supplied_ami_id
  vpc_id                    = module.aws-vpc.vpc_id
  env                       = var.env
  private_ip_monitoring     = var.private_ip_monitoring
  depends_on                = [module.cas_certs_route53]
}

module "monitoring" {
  source = "./modules/monitoring"

  allowed_inbound_cidrs      = var.allowed_inbound_cidrs_lb
  allowed_inbound_cidrs_ssh  = var.allowed_inbound_cidrs_ssh
  aws_iam_instance_profile   = module.iam.aws_iam_instance_profile
  common_tags                = var.common_tags
  instance_type              = var.instance_type
  monitoring_key_name        = module.secrets.bastion_key_name
  lb_type                    = var.lb_type
  monitoring_node_count      = var.monitoring_node_count
  monitoring_subnets         = module.aws-vpc.private_subnet_ids
  resource_name_prefix       = var.resource_name_prefix
  userdata_monitoring_script = module.user_data.monitoring_userdata_base64_encoded
  user_supplied_ami_id       = var.user_supplied_ami_id
  vpc_id                     = module.aws-vpc.vpc_id
  env                        = var.env
  private_ip_monitoring      = var.private_ip_monitoring
  depends_on                 = [module.aws-vpc, module.cas_certs_route53, module.route53, module.loadbalancer]
}
