variable "instance_id" { type = string }
variable "name" { type = string }


output "kubeconfig" { value = data.template_file.kubeconfig.rendered }
output "server" { value = data.aws_eks_cluster.main.endpoint }
output "certificate_authority_data" { value = data.aws_eks_cluster.main.certificate_authority[0].data }
output "token" { value = base64encode(data.kubernetes_secret.secret.data.token) }
output "namespace" { value = local.namespace }

locals {
  name         = var.name != "" ? var.name : random_id.name.hex
  cluster_name = "k8s-${substr(sha256(var.instance_id), 0, 16)}"
  namespace    = "default"
}

provider "kubernetes" {
  version                = "~> 1.13.3"
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    args        = ["token", "--cluster-id", data.aws_eks_cluster.main.id]
    command     = "aws-iam-authenticator"
  }
}


data "aws_eks_cluster" "main" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "main" {
  name = local.cluster_name
}

data "kubernetes_config_map" "binding_info" {
  metadata {
    name = "binding-info"
  }
}

# Randomly generated name, if one wasn't supplied
resource "random_id" "name" {
  byte_length = 8
}

# Create a service account with that name for the target namespace
resource "kubernetes_service_account" "account" {
  metadata {
    name      = local.name
    namespace = local.namespace
  }
}

# Bind the namespace-admin role to the service account
resource "kubernetes_role_binding" "binding" {
  metadata {
    name      = "${kubernetes_service_account.account.metadata[0].name}-admin-role-binding"
    namespace = local.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "namespace-admin"
  }

  subject {
    api_group = ""
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.account.metadata[0].name
    namespace = local.namespace
  }
}

# Read in the generated secret for the service account
data "kubernetes_secret" "secret" {
  metadata {
    name      = kubernetes_service_account.account.default_secret_name
    namespace = local.namespace
  }
}

# Generate a kubeconfig file for using the service account
data "template_file" "kubeconfig" {
  template = <<-EOF
    apiVersion: v1
    kind: Config
    users:
    - name: ${kubernetes_service_account.account.metadata[0].name}
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
        namespace: ${local.namespace}
        user: ${kubernetes_service_account.account.metadata[0].name}
      name: ${data.aws_eks_cluster.main.name}-${local.namespace}-${kubernetes_service_account.account.metadata[0].name}
    current-context: ${data.aws_eks_cluster.main.name}-${local.namespace}-${kubernetes_service_account.account.metadata[0].name}
  EOF
}
