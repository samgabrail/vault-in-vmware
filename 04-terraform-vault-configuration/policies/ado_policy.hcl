### ado-pipeline.hcl
# Read-only permission on 'internal/data/azure*' path
path "internal/data/azure" {
  capabilities = [ "read" ]
}

# Read-only permission on 'internal/azure*' path
path "internal/azure" {
  capabilities = [ "read" ]
}

path "auth/token/create" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
###
