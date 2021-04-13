provider "aws" {
  # We need at least 3.16.0 because it fixes a problem with creating/deleting
  # Fargate profiles in parallel. See this issue for more information:
  # https://github.com/hashicorp/terraform-provider-aws/issues/13372#issuecomment-729689441
  # version = "~> 3.16.0"
  # Using 2.67.0 so that Route53 that was developed using the eks cluster works with the Fargate
  version = "~> 2.67.0"
  region  = local.region
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    args        = ["token", "--cluster-id", data.aws_eks_cluster.main.id]
    command     = "aws-iam-authenticator"
  }
  version = "~> 1.13.3"
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    load_config_file       = false
    config_path            = "./kubeconfig_${module.eks.cluster_id}"
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = ["token", "--cluster-id", data.aws_eks_cluster.main.id]
      command     = "aws-iam-authenticator"
    }
  }
  # Helm 2.0.1 seems to have issues with alias. When alias is removed the helm_release provider working
  # Using Helm < 2.0.1 version seem to solve the issue.
  # version = "~> 1.2"
  version = "1.2.0"
}

