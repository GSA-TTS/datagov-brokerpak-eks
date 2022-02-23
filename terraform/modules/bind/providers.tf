provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["token", "--cluster-id", data.aws_eks_cluster.main.id]
    command     = "aws-iam-authenticator"
    env = {
      AWS_ACCESS_KEY_ID = var.aws_access_key_id,
      AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
    }
  }
}
