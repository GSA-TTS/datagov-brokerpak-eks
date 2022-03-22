locals {
  cluster_name = "k8s-${substr(sha256(var.instance_name), 0, 16)}"
  namespace    = "default"
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
        certificate-authority-data: ${var.certificate_authority_data}
        server: ${var.server}
      name: ${local.cluster_name}
    contexts:
    - context:
        cluster: ${local.cluster_name}
        namespace: ${local.namespace}
        user: ${kubernetes_service_account.account.metadata[0].name}
      name: ${local.cluster_name}-${local.namespace}-${kubernetes_service_account.account.metadata[0].name}
    current-context: ${local.cluster_name}-${local.namespace}-${kubernetes_service_account.account.metadata[0].name}
  EOF
}
