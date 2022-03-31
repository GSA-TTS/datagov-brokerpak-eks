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
resource "kubernetes_cluster_role_binding" "admin" {
  metadata {
    name = "${kubernetes_service_account.admin.metadata[0].name}-cluster-role-binding"
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
        certificate-authority-data: ${local.certificate_authority_data}
        server: ${local.server}
      name: ${local.cluster_name}
    contexts:
    - context:
        cluster: ${local.cluster_name}
        namespace: "kube-system"
        user: ${kubernetes_service_account.admin.metadata[0].name}
      name: ${local.cluster_name}-kube-system-${kubernetes_service_account.admin.metadata[0].name}
    current-context: ${local.cluster_name}-kube-system-${kubernetes_service_account.admin.metadata[0].name}
  EOF
}

resource "kubernetes_role" "namespace_admin" {
  # TODO: create one of these in every requested namespace
  metadata {
    name      = "namespace-admin"
    namespace = "default"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}
