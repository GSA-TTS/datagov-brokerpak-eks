resource "helm_release" "calico" {
  name            = "calico"
  chart           = "projectcalico"
  repository      = "https://docs.projectcalico.org/charts"
  version         = "3.20.2"
  namespace       = "kube-system"
  cleanup_on_fail = "true"
  atomic          = "true"

  dynamic "set" {
    for_each = {
      "installation.kubernetesProvider"   = "EKS"
    }
    content {
      name = set.key
      value = set.value
    }
  }
  depends_on = [
    null_resource.cluster-functional,
  ]
}

resource "kubernetes_network_policy" "default-deny" {
  metadata {
    name      = "default-deny"
    namespace = "default"
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy" "eks" {
  count = (var.ingress_allowed != null || var.egress_allowed != null ? 1 : 0)
  metadata {
    name      = "eks-clusters-network-policy"
    namespace = "default"
  }

  lifecycle {
    ignore_changes = all
  }

  spec {
    pod_selector {}

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "default"
          }
        }
      }

      from {
        ip_block {
          cidr = var.ingress_allowed
          except = var.ingress_disallowed
        }
      }
    }

    egress {
      to {
        ip_block {
          cidr = var.egress_allowed
          except = var.egress_disallowed
        }
      }
    }

    policy_types = ["Ingress", "Egress"]
  }
}
