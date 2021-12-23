
# Create a namespace-level admin role for each namespace
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

  depends_on = [
    null_resource.cluster-functional,
  ]
}

# Admin roles may additionally need to list namespaces.
# For example, if using the kubernetes_namespace data source in Terraform)
resource "kubernetes_cluster_role" "namespace_reader" {
  metadata {
    name = "namespace-reader"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["list", "get"]
  }

  depends_on = [
    null_resource.cluster-functional,
  ]
}

