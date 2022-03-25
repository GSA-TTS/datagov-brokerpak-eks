
resource "kubernetes_namespace" "calico-system" {
  metadata {
    annotations = {
      name = "calico-system"
    }
    name = "calico-system"
  }
}

resource "kubernetes_network_policy" "default-deny" {
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
