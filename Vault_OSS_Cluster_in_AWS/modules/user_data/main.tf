

locals {
  vault_user_data = templatefile(
    "${path.module}/templates/install_vault.sh.tpl",
    {
      region                = var.aws_region
      name                  = var.resource_name_prefix
      vault_version         = var.vault_version
      kms_key_arn           = var.kms_key_arn
      secrets_manager_arn   = var.secrets_manager_arn
      leader_tls_servername = var.leader_tls_servername
      DATADOG_API_KEY       = var.DATADOG_API_KEY
      env                   = var.env
      vault_version         = var.vault_version
      private_ip_monitoring = var.private_ip_monitoring
      # VAULT_LICENSE         = var.VAULT_LICENSE
    }
  )
  bastion_user_data = templatefile(
    "${path.module}/templates/install_bastion.tpl",
    {
      region                = var.aws_region
      name                  = var.resource_name_prefix
      vault_version         = var.vault_version
      kms_key_arn           = var.kms_key_arn
      secrets_manager_arn   = var.secrets_manager_arn
      leader_tls_servername = var.leader_tls_servername
      DATADOG_API_KEY       = var.DATADOG_API_KEY
      env                   = var.env
      vault_version         = var.vault_version
      lb_fqdn               = var.lb_fqdn
      subordinate_ca_arn    = var.subordinate_ca_arn
    }
  )
  monitoring_user_data = templatefile(
    "${path.module}/templates/install_monitoring.tpl",
    {
      region              = var.aws_region
      name                = var.resource_name_prefix
      DATADOG_API_KEY     = var.DATADOG_API_KEY
      env                 = var.env
      subordinate_ca_arn  = var.subordinate_ca_arn
      secrets_manager_arn = var.secrets_manager_arn
    }
  )
}
