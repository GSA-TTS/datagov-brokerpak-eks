
resource "kubernetes_manifest" "autoscaler-provisioner" {
  manifest = {
    "apiVersion" = "karpenter.sh/v1alpha5"
    "kind" = "Provisioner"
    "metadata" = {
      "name" = "default-provisioner"
    }
    "spec" = {
      "limits" = {
        "resources" = {
          "cpu" = 1000
        }
      }
      "provider" = {
        "launchTemplate" = local.launch_template_name
        "subnetSelector" = {
          "karpenter.sh/discovery" = local.cluster_name
        }
      }
      "requirements" = [
        {
          "key" = "karpenter.sh/capacity-type"
          "operator" = "In"
          "values" = [
            "on-demand",
          ]
        },
      ]
      "ttlSecondsAfterEmpty" = 30
    }
  }
  depends_on = [
    null_resource.cluster-functional,
    helm_release.karpenter
  ]
}
