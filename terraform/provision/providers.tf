provider "aws" {
  region = local.region
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key
}

# A separate provider for creating KMS keys in the us-east-1 region, which
# is required for DNSSEC. See
# https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-configuring-dnssec-cmk-requirements.html
provider "aws" {
  alias  = "dnssec_key_provider"
  region = "us-east-1"
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key
}


provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["token", "--cluster-id", data.aws_eks_cluster.main.id]
    command     = "aws-iam-authenticator"
    env         = {
      AWS_PROFILE = "tf"
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["token", "--cluster-id", data.aws_eks_cluster.main.id]
      command     = "aws-iam-authenticator"
      env         = {
        AWS_PROFILE = "tf"
      }
    }
  }
}

