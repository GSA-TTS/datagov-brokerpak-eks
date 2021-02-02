variable "cluster_id" { type = string }
variable "name" { 
  type = string 
  default = ""
}

output "namespace" { value = kubernetes_namespace.binding.metadata[0].name }

locals {
  name        = var.name != "" ? var.name : "ns-${random_id.name.hex}"
}

resource "random_id" "name" {
  byte_length = 8
}

provider "kubernetes" {
  version = "~> 1.13.3"
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    args        = ["token", "--cluster-id", data.aws_eks_cluster.main.id]
    command     = "aws-iam-authenticator"
  }
}

resource "kubernetes_namespace" "binding" {
  metadata {
    name = local.name
    annotations = {}
  }
}

data "aws_eks_cluster" "main" {
  name  = var.cluster_id
}

data "aws_eks_cluster_auth" "main" {
  name  = var.cluster_id
}

data "aws_iam_role" "iam_role_fargate" {
  name = "eks-fargate-profile-${data.aws_eks_cluster.main.name}"
}

resource "aws_eks_fargate_profile" "binding" {
  cluster_name           = data.aws_eks_cluster.main.name
  fargate_profile_name   = kubernetes_namespace.binding.metadata[0].name
  pod_execution_role_arn = data.aws_iam_role.iam_role_fargate.arn
  subnet_ids             = data.aws_eks_cluster.main.vpc_config[0].subnet_ids
  selector {
    namespace = kubernetes_namespace.binding.metadata[0].name
  }
}

# Create a service account for the namespace
resource "kubernetes_service_account" "namespace_admin" {
  metadata {
    name = "admin"
    namespace     = kubernetes_namespace.binding.metadata[0].name
  }
}


# A namespace-level admin role
resource "kubernetes_role" "namespace_admin" {
  metadata {
    name        = "namespace-admin"
    namespace   = kubernetes_namespace.binding.metadata[0].name
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

# Bind the namespace-admin role to the service account
resource "kubernetes_role_binding" "service_account_role_binding" {
  metadata {
    name      = "${kubernetes_service_account.namespace_admin.metadata[0].name}-admin-role-binding"
    namespace = kubernetes_namespace.binding.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "namespace-admin"
  }

  subject {
    api_group = ""
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.namespace_admin.metadata[0].name
    namespace = kubernetes_namespace.binding.metadata[0].name
  }
}

# Read in the generated (default) secret for the service account
data "kubernetes_secret" "secret" { 
  metadata {
    name = kubernetes_service_account.namespace_admin.default_secret_name
    namespace = kubernetes_namespace.binding.metadata[0].name
  }
}