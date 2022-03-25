
resource "kubernetes_namespace" "calico-system" {
  metadata {
    annotations = {
      name = "calico-system"
    }
    name = "calico-system"
  }
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

resource "kubernetes_network_policy" "default-deny" {
  for_each = toset(local.namespace_list)
  
  metadata {
    name      = "default-deny-egress"
    namespace = "default"
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]
  }
}

resource "helm_release" "calico" {
  name       = "calico"
  namespace  = "calico-system"
  wait       = true
  atomic     = true
  repository = "https://docs.projectcalico.org/charts"
  chart      = "tigera-operator"
  version    = "v3.22.1"
}
