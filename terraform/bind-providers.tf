provider "kubernetes" {
  alias = "bind"
  host                   = module.provision.host
  cluster_ca_certificate = base64decode(module.provision.cluster_ca_certificate)
  token                  = module.provision.token

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["token", "--cluster-id", module.provision.cluster-id]
    command     = "aws-iam-authenticator"
    env = {
      AWS_ACCESS_KEY_ID = var.aws_access_key_id,
      AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
    }
  }
}
