path "azure/*" {
  capabilities = [ "read" ]
}
path "auth/approle/role/webblog-approle/role-id" {
  policy = "read"
}
path "auth/approle/role/webblog-approle/secret-id" {
  policy = "write"
  min_wrapping_ttl   = "100s"
  max_wrapping_ttl   = "1000s"
}
path "internal/data/tfc" {
  capabilities = ["read"]
}
path "internal/data/webblog/mongodb" {
  capabilities = ["read"]
}