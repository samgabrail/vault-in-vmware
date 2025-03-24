path "auth/pipeline/role/pipeline-approle/secret-id" {
  policy = "write"
  min_wrapping_ttl   = "100s"
  max_wrapping_ttl   = "300s"
}