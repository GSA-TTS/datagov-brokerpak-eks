variable "instance_id" { type = string }
variable "name" { type = string }


output "kubeconfig" { value = data.template_file.kubeconfig.rendered }
output "server" { value = data.aws_eks_cluster.main.endpoint }
output "certificate_authority_data" { value = data.aws_eks_cluster.main.certificate_authority[0].data }
output "token" { value = data.kubernetes_secret.secret.data.token}
output "namespace" { value = kubernetes_namespace.binding.id}

locals {
  name        = var.name != "" ? var.name : "ns-${random_id.name.hex}"
  cluster_name = trim(var.instance_id,"- ")
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
  name  = local.cluster_name
}

data "aws_eks_cluster_auth" "main" {
  name  = local.cluster_name
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

# Generate a kubeconfig file for using the service account
data "template_file" "kubeconfig" {
  template = <<-EOF
    apiVersion: v1
    kind: Config
    users:
    - name: ${kubernetes_namespace.binding.id}-admin
      user:
        token: ${data.kubernetes_secret.secret.data.token}
    clusters:
    - cluster:
        certificate-authority-data: ${data.aws_eks_cluster.main.certificate_authority[0].data}
        server: ${data.aws_eks_cluster.main.endpoint}
      name: ${data.aws_eks_cluster.main.name}
    contexts:
    - context:
        cluster: ${data.aws_eks_cluster.main.name}
        namespace: ${kubernetes_namespace.binding.id}
        user: ${kubernetes_namespace.binding.id}-admin
      name: ${data.aws_eks_cluster.main.name}-${kubernetes_namespace.binding.id}
    current-context: ${data.aws_eks_cluster.main.name}-${kubernetes_namespace.binding.id}
  EOF
}