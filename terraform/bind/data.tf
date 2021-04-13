locals {
  name         = var.name != "" ? var.name : random_id.name.hex
  cluster_name = "k8s-${substr(sha256(var.instance_id), 0, 16)}"
  namespace    = "default"
}

data "aws_eks_cluster" "main" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "main" {
  name = local.cluster_name
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
