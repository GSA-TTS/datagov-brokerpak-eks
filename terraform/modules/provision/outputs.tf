output "domain_name" { value = local.domain }
output "host" { value = data.aws_eks_cluster.main.endpoint }
output "cluster_ca_certificate" { value = data.aws_eks_cluster.main.certificate_authority[0].data }
output "token" { value = data.aws_eks_cluster_auth.main.token }
output "cluster-id" { value = data.aws_eks_cluster.main.id }