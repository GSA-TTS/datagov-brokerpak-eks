output "domain_name" { value = local.domain }
output "server" { value = data.aws_eks_cluster.main.endpoint }
output "certificate_authority_data" { value = data.aws_eks_cluster.main.certificate_authority[0].data }
output "cluster-id" { value = data.aws_eks_cluster.main.id }
output "zone_id" { value = aws_route53_zone.cluster.zone_id }
output "zone_role_arn" { value = aws_iam_role.external_dns.arn}