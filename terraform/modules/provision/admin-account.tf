# Randomly generated name, if one wasn't supplied
resource "random_id" "name" {
  byte_length = 8
}

# Create a service account with that name in the kube-system namespace
resource "kubernetes_service_account" "admin" {
  metadata {
    name      = "admin-${random_id.name.hex}"
    namespace = "kube-system"
  }
}

# Bind the service account to the cluster-admin role
resource "kubernetes_cluster_role_binding" "binding" {
  metadata {
    name      = "${kubernetes_service_account.admin.metadata[0].name}-cluster-role-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.admin.metadata[0].name
    namespace = "kube-system"
  }
}

# Read in the generated secret for the service account
data "kubernetes_secret" "secret" {
  metadata {
    name      = kubernetes_service_account.admin.default_secret_name
    namespace = "kube-system"
  }
}

# Generate a kubeconfig file with a token for the admin service account (which removes
# the need for consumers to use aws-iam-authenticator or another binary).
data "template_file" "admin_kubeconfig" {
  template = <<-EOF
    apiVersion: v1
    kind: Config
    users:
    - name: ${kubernetes_service_account.admin.metadata[0].name}
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
        namespace: "kube-system"
        user: ${kubernetes_service_account.admin.metadata[0].name}
      name: ${data.aws_eks_cluster.main.name}-kube-system-${kubernetes_service_account.admin.metadata[0].name}
    current-context: ${data.aws_eks_cluster.main.name}-kube-system-${kubernetes_service_account.admin.metadata[0].name}
  EOF
}