# Randomly generated name, if one wasn't supplied
resource "random_id" "name" {
  byte_length = 8
}

# Create a service account with that name for the target namespace
resource "kubernetes_service_account" "account" {
  metadata {
    name      = random_id.name.hex
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