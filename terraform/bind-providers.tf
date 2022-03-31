provider "kubernetes" {
  alias                  = "bind"
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = module.provision-k8s.token
}
