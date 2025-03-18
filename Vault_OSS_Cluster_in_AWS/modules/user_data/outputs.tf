output "vault_userdata_base64_encoded" {
  value = base64encode(local.vault_user_data)
}

output "bastion_userdata_base64_encoded" {
  value = base64encode(local.bastion_user_data)
}

output "monitoring_userdata_base64_encoded" {
  value = base64encode(local.monitoring_user_data)
}
