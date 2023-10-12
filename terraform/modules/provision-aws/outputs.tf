output "domain_name" { value = local.domain }
output "server" { value = module.eks.cluster_endpoint }
output "certificate_authority_data" { value = module.eks.cluster_certificate_authority_data }
output "cluster-id" { value = module.eks.cluster_name }
