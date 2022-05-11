
resource "kubernetes_namespace" "calico-system" {
  metadata {
    annotations = {
      name = "calico-system"
    }
    name = "calico-system"
  }
}

resource "helm_release" "calico" {
  name       = "calico"
  namespace  = kubernetes_namespace.calico-system.id
  wait       = true
  atomic     = true
  repository = "https://docs.projectcalico.org/charts"
  chart      = "tigera-operator"
  version    = "v3.22.1"
  depends_on = [
    null_resource.cluster-functional
  ]
}

locals {
  # In future, we will extend this list
  #   1. To account for additional namespaces having been provisioned
  #     See https://github.com/GSA/data.gov/issues/3013
  #   2. To lock down "admin" namespaces and then selectively add allow policies
  #     For example, add default-deny in kube-system, then add a separate explicit
  #     allow policy for things that need to use AWS APIs like the 
  #     aws-load-balancer-controller
  # ...but for now, we only care about the place where consumers will put their 
  # workloads.
  namespace_list = ["default"]
}

resource "kubernetes_network_policy" "default" {
  for_each = toset(local.namespace_list)

  lifecycle {
    ignore_changes = [
      # We need the policy to exist at the outset, and we need to clean it up
      # during a destroy. However, people can edit this policy after initial
      # deployment and we won't set it back. It's a "customer responsibility" to
      # evaluate the security of changing the default (or adding additional
      # NetworkPolicies that allow egress traffic).
      spec
    ]
  }
  metadata {
    name      = "default-deny-egress-and-cloud-gov-ingress"
    namespace = each.key
  }

  spec {
    pod_selector {}

    ingress {
      from {
        ip_block {
          cidr = local.vpc_cidr_block
        }
      }
      from {
        ip_block {
          cidr = "52.222.122.97/32"
        }
      }
      from {
        ip_block {
          cidr = "52.222.123.172/32"
        }
      }
    }

    policy_types = ["Ingress", "Egress"]
  }
}
