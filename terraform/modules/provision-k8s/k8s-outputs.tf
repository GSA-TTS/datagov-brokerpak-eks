output "token" {
  value       = kubernetes_secret.admin.data.token
  description = "A cluster-admin token for use in constructing your own kubernetes configuration. NOTE: Do _not_ use this token when configuring the required_provider or you'll get a dependency cycle. Instead use exec with the same AWS credentials that were used for the required_providers aws provider."
  sensitive   = true
}
