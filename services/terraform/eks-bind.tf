variable "kubeconfig" { type = string }
locals {
  raw_data     = yamldecode(var.kubeconfig)
  cluster_name = local.raw_data.clusters[0].name
}
output "cluster_ca_certificate" { value = local.raw_data.clusters[0].cluster.certificate-authority-data }
output "server" { value = local.raw_data.clusters[0].cluster.server }
output "token" { value = data.aws_eks_cluster_auth.instance.token }

# Get a token for the cluster in question
data "aws_eks_cluster_auth" "instance" {
  name  = local.cluster_name
}

# TODO: 
# 1) Fire up the kubernetes provider
# 2) Create a namespace
# 3) Create a Fargate profile for that namespace
# 4) Generate a role and secret with access to that namespace only (like in solroperator/operator-bind.tf)

# provider "kubernetes" {
#   host                   = var.server
#   cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
#   token                  = base64decode(var.token)
#   load_config_file       = false
# }
