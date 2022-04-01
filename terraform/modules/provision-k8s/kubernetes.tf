provider "kubernetes" {
  host                   = var.server
  cluster_ca_certificate = base64decode(var.certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    args        = ["token", "--cluster-id", local.cluster_name]
    command     = "aws-iam-authenticator"
  }
}
provider "helm" {
  kubernetes {
    host                   = var.server
    cluster_ca_certificate = base64decode(var.certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = ["token", "--cluster-id", local.cluster_name]
      command     = "aws-iam-authenticator"
    }
  }
}
