output "domain_name" { value = local.domain }
output "server" { value = data.aws_eks_cluster.main.endpoint }
output "certificate_authority_data" { value = data.aws_eks_cluster.main.certificate_authority[0].data }
output "cluster-id" { value = data.aws_eks_cluster.main.id }
output "token" { 
  value = data.kubernetes_secret.secret.data.token
  description = "A cluster-admin token for use in constructing your own kubernetes configuration. NOTE: Do _not_ use this token when configuring the required_provider or you'll get a dependency cycle. Instead use exec with the same AWS credentials that were used for the required_providers aws provider."
}
