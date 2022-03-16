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

# Make the service account an admin within the namespace. See
# https://kubernetes.io/docs/reference/access-authn-authz/rbac/#user-facing-roles.
resource "kubernetes_role_binding" "binding" {
  metadata {
    name      = "${kubernetes_service_account.account.metadata[0].name}-namespace-admin-role-binding"
    namespace = local.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }

  subject {
    api_group = ""
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.account.metadata[0].name
    namespace = local.namespace
  }
}