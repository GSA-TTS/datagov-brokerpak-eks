resource "kubernetes_network_policy" "eks" {
  metadata {
    name      = "eks-clusters-network-policy"
    namespace = "default"
  }

  lifecycle {
    ignore_changes = all
  }

  spec {
    pod_selector {
      match_expressions {
        key      = "name"
        operator = "In"
        values   = ["webfront", "api"]
      }
    }

    ingress {
      ports {
        port     = "http"
        protocol = "tcp"
      }
      ports {
        port     = "https"
        protocol = "tcp"
      }

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
