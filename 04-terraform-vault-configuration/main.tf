terraform {
  required_providers {
    vault = {
      source = "hashicorp/vault"
      version = "2.15.0"
    }
    azurerm = {
      source = "hashicorp/azurerm"
      version = "2.36.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  features {}
}

provider "vault" {
  # Configuration options
}

resource "vault_auth_backend" "example" {
  type = "userpass"
}

resource "vault_policy" "admin_policy" {
  name   = "admins"
  policy = file("policies/admin_policy.hcl")
}

resource "vault_policy" "developer_policy" {
  name   = "developers"
  policy = file("policies/developer_policy.hcl")
}

resource "vault_policy" "operations_policy" {
  name   = "operations"
  policy = file("policies/operation_policy.hcl")
}

resource "vault_policy" "ado_policy" {
  name   = "ado_policy"
  policy = file("policies/ado_policy.hcl")
}

resource "vault_mount" "developers" {
  path        = "developers"
  type        = "kv-v2"
  description = "KV2 Secrets Engine for Developers."
}

resource "vault_mount" "operations" {
  path        = "operations"
  type        = "kv-v2"
  description = "KV2 Secrets Engine for Operations."
}

resource "vault_generic_secret" "developer_sample_data" {
  path = "${vault_mount.developers.path}/test_account"

  data_json = <<EOT
{
  "username": "foo",
  "password": "bar"
}
EOT
}

// WebBlog Config

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

// resource "vault_kubernetes_auth_backend_config" "kubernetes_config" {
//   kubernetes_host    = "<K8s_host>"
//   kubernetes_ca_cert = "<K8s_cert>"
//   token_reviewer_jwt = "<jwt_token>"
// }

// You could use the above stanza to configure the K8s auth method by providing the proper values or do this manually inside the Vault container:
// vault write auth/kubernetes/config \
//    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
//    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
//    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

resource "vault_kubernetes_auth_backend_role" "webblog" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "webblog"
  bound_service_account_names      = ["webblog"]
  bound_service_account_namespaces = ["webblog"]
  token_ttl                        = 86400
  token_policies                   = ["webblog"]
}

resource "vault_policy" "webblog" {
  name   = "webblog"
  policy = file("policies/webblog_policy.hcl")
}

resource "vault_mount" "internal" {
  path        = "internal"
  type        = "kv-v2"
  description = "KV2 Secrets Engine for WebBlog MongoDB."
}

resource "vault_generic_secret" "webblog" {
  path = "${vault_mount.internal.path}/webblog/mongodb"

  data_json = <<EOT
{
  "username": "${var.DB_USER}",
  "password": "${var.DB_PASSWORD}"
}
EOT
}

resource "vault_generic_secret" "azure" {
  path = "${vault_mount.internal.path}/azure"

  data_json = <<EOT
{
  "subscription_id": "${var.subscription_id}",
  "tenant_id": "${var.tenant_id}",
  "client_secret": "${var.client_secret}",
  "client_id": "${var.client_id}"
}
EOT
}

resource "vault_mount" "db" {
  path = "mongodb"
  type = "database"
  description = "Dynamic Secrets Engine for WebBlog MongoDB."
}

resource "vault_mount" "db_nomad" {
  path = "mongodb_nomad"
  type = "database"
  description = "Dynamic Secrets Engine for WebBlog MongoDB on Nomad."
}

resource "vault_mount" "db_azure" {
  path = "mongodb_azure"
  type = "database"
  description = "Dynamic Secrets Engine for WebBlog MongoDB on Azure."
}

resource "vault_database_secret_backend_connection" "mongodb" {
  backend       = vault_mount.db.path
  name          = "mongodb"
  allowed_roles = ["mongodb-role"]

  mongodb {
    connection_url = "mongodb://${var.DB_USER}:${var.DB_PASSWORD}@${var.DB_URL}/admin"
    
  }
}

resource "vault_database_secret_backend_connection" "mongodb_nomad" {
  backend       = vault_mount.db_nomad.path
  name          = "mongodb_nomad"
  allowed_roles = ["mongodb-nomad-role"]

  mongodb {
    connection_url = "mongodb://${var.DB_USER}:${var.DB_PASSWORD}@${var.DB_URL_NOMAD}/admin"
    
  }
}

resource "vault_database_secret_backend_connection" "mongodb_azure" {
  backend       = vault_mount.db_azure.path
  name          = "mongodb_azure"
  allowed_roles = ["mongodb-azure-role"]

  mongodb {
    connection_url = "mongodb://${var.DB_USER}:${var.DB_PASSWORD}@${var.DB_URL_AZURE}/admin"
    
  }
}

resource "vault_database_secret_backend_role" "mongodb-role" {
  backend             = vault_mount.db.path
  name                = "mongodb-role"
  db_name             = vault_database_secret_backend_connection.mongodb.name
  default_ttl         = "10"
  max_ttl             = "86400"
  creation_statements = ["{ \"db\": \"admin\", \"roles\": [{ \"role\": \"readWriteAnyDatabase\" }, {\"role\": \"read\", \"db\": \"foo\"}] }"]
}

resource "vault_database_secret_backend_role" "mongodb-nomad-role" {
  backend             = vault_mount.db_nomad.path
  name                = "mongodb-nomad-role"
  db_name             = vault_database_secret_backend_connection.mongodb_nomad.name
  default_ttl         = "10"
  max_ttl             = "86400"
  creation_statements = ["{ \"db\": \"admin\", \"roles\": [{ \"role\": \"readWriteAnyDatabase\" }, {\"role\": \"read\", \"db\": \"foo\"}] }"]
}

resource "vault_database_secret_backend_role" "mongodb-azure-role" {
  backend             = vault_mount.db_azure.path
  name                = "mongodb-azure-role"
  db_name             = vault_database_secret_backend_connection.mongodb_azure.name
  default_ttl         = "10"
  max_ttl             = "86400"
  creation_statements = ["{ \"db\": \"admin\", \"roles\": [{ \"role\": \"readWriteAnyDatabase\" }, {\"role\": \"read\", \"db\": \"foo\"}] }"]
}


resource "vault_mount" "transit" {
  path                      = "transit"
  type                      = "transit"
  description               = "To Encrypt the webblog"
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 86400
}

resource "vault_transit_secret_backend_key" "key" {
  backend = vault_mount.transit.path
  name    = "webblog-key"
  derived = "true"
  convergent_encryption = "true"
}

locals {
  se-region = "AMER - Canada"
  owner     = "sam.gabrail"
  purpose   = "demo for end-to-end infrastructure and application deployments"
  ttl       = "720"
  terraform = "true"
}

locals {
  # Common tags to be assigned to all resources
  common_tags = {
    se-region = local.se-region
    owner     = local.owner
    purpose   = local.purpose
    ttl       = local.ttl
    terraform = local.terraform
  }
}

# Azure Secrets Engine Configuration
resource "azurerm_resource_group" "myresourcegroup" {
  name     = "${var.prefix}-jenkins"
  location = var.location

  tags = local.common_tags
}

resource "vault_azure_secret_backend" "azure" {
  subscription_id = var.subscription_id
  tenant_id = var.tenant_id
  client_secret = var.client_secret
  client_id = var.client_id
}

resource "vault_azure_secret_backend_role" "jenkins" {
  backend                     = vault_azure_secret_backend.azure.path
  role                        = "jenkins"
  ttl                         = "24h"
  max_ttl                     = "48h"

  azure_roles {
    role_name = "Contributor"
    scope =  "/subscriptions/${var.subscription_id}/resourceGroups/${azurerm_resource_group.myresourcegroup.name}"
  }
}

# Jenkins Secure Introduction

resource "vault_policy" "jenkins_policy" {
  name = "jenkins-policy"
  policy = file("policies/jenkins_policy.hcl")
}

resource "vault_auth_backend" "jenkins_access" {
  type = "approle"
  path = "jenkins"
}

resource "vault_approle_auth_backend_role" "jenkins_approle" {
  backend            = vault_auth_backend.jenkins_access.path
  role_name          = "jenkins-approle"
  //secret_id_num_uses = "0"  means unlimited 
  secret_id_num_uses = "0" 
  token_policies     = ["default", "jenkins-policy"]
}

resource "vault_policy" "pipeline_policy" {
  name = "pipeline-policy"
  policy = file("policies/jenkins_pipeline_policy.hcl")
}

resource "vault_auth_backend" "pipeline_access" {
  type = "approle"
  path = "pipeline"
}

resource "vault_approle_auth_backend_role" "pipeline_approle" {
  backend            = vault_auth_backend.pipeline_access.path
  role_name          = "pipeline-approle"
  secret_id_num_uses = "1"
  secret_id_ttl      = "300"
  token_ttl          = "1800"
  token_policies     = ["default", "pipeline-policy"]
}

resource "vault_auth_backend" "apps_access" {
  type = "approle"
  path = "approle"
}

resource "vault_approle_auth_backend_role" "webblog_approle" {
  backend            = vault_auth_backend.apps_access.path
  role_name          = "webblog-approle"
  secret_id_num_uses = "1"
  secret_id_ttl      = "600"
  token_ttl          = "1800"
  token_policies     = ["default", "webblog"]
}
