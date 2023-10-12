# This is a workaround to use CRDs in the same Terraform pass as they are made
# available. Explanation:
# https://github.com/GSA/datagov-brokerpak-eks/pull/67#issuecomment-1093641392
resource "helm_release" "autoscaler-provisioner" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.29.3"

  dynamic "set" {
    for_each = {
      "autoDiscovery.clusterName" = local.cluster_name
      "awsRegion" = data.aws_region.current.name

      # { "karpenter.sh/discovery" = local.cluster_name },
      # { "k8s.io/cluster-autoscaler/enabled" = true },
      # { "k8s.io/cluster-autoscaler/${local.cluster_name}" = local.cluster_name },
      # { "autoDiscovery.clusterName" = local.cluster_name },
      # { "awsRegion" = data.aws_region.current.name },
      }
    content {
      name  = set.key
      value = set.value
    }
  }

  depends_on = [
    null_resource.cluster-functional,
    helm_release.karpenter
  ]
}
