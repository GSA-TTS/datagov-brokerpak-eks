resource "kubernetes_namespace" "starboard-system" {
  metadata {
    annotations = {
      name = "starboard-system"
    }

    name = "starboard-system"
  }
  depends_on = [
    null_resource.cluster-functional
  ]
}

resource "helm_release" "starboard-operator" {
  name       = "starboard-operator"
  namespace  = kubernetes_namespace.starboard-system.id
  wait       = true
  atomic     = true
  repository = "https://aquasecurity.github.io/helm-charts/"
  chart      = "starboard-operator"
  version    = "0.10.12"

  values = [
    <<-EOF
  EOF
  ]

  dynamic "set" {
    for_each = {
      # Once we're able to pull from the public ECR repository, we should uncomment these.
      # "trivy.imageRef"      = "public.ecr.aws/aquasecurity/trivy:0.25.3"
      # "image.repository"    = "public.ecr.aws/aquasecurity/starboard-operator"

      # Starboard docs all show this set to true; unclear if that's just an example of setting a value!
      # The default is false; see https://artifacthub.io/packages/helm/statcan/starboard-operator?modal=values
      # "trivy.ignoreUnfixed" = true
      "replicas" = 1
    }
    content {
      name  = set.key
      value = set.value
    }
  }
}
