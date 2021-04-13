
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
    aws_eks_fargate_profile.default_namespaces
  ]
}
