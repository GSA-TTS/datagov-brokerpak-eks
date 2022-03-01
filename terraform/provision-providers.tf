variable "aws_access_key_id" {
  type = string
}

variable "aws_secret_access_key" {
  type = string
}

provider "kubernetes" {
  alias                  = "provision"
  host                   = module.provision.server
  cluster_ca_certificate = base64decode(module.provision.certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    args        = ["token", "--cluster-id", module.provision.cluster-id]
    command     = "aws-iam-authenticator"
    env = {
      AWS_ACCESS_KEY_ID     = var.aws_access_key_id,
      AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
    }
  }
}

provider "helm" {
  alias = "provision"
  debug = true
  kubernetes {
    host                   = module.provision.server
    cluster_ca_certificate = base64decode(module.provision.certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = ["token", "--cluster-id", module.provision.cluster-id]
      command     = "aws-iam-authenticator"
      env = {
        AWS_ACCESS_KEY_ID     = var.aws_access_key_id,
        AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
      }
    }
  }
}

