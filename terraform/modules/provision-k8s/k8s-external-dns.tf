# Modeled after an example here:
# https://tech.polyconseil.fr/external-dns-helm-terraform.html

resource "kubernetes_service_account" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = local.zone_role_arn
    }
  }
  automount_service_account_token = true
}

resource "kubernetes_cluster_role" "external_dns" {
  metadata {
    name = "external-dns"
  }

  rule {
    api_groups = [""]
    resources  = ["services", "pods", "nodes", "endpoints"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["extensions", "networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["networking.istio.io"]
    resources  = ["gateways"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "external_dns" {
  metadata {
    name = "external-dns"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.external_dns.metadata.0.name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.external_dns.metadata.0.name
    namespace = kubernetes_service_account.external_dns.metadata.0.namespace
  }
}

# Chart docs: https://github.com/bitnami/charts/tree/master/bitnami/external-dns/
resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = kubernetes_service_account.external_dns.metadata.0.namespace
  wait       = true
  atomic     = true
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = "1.7.1"

  values = [
    <<-EOF
    env:
      - name: AWS_DEFAULT_REGION
        value: ${local.region}
    extraArgs:
      - --zone-id-filter=${local.zone_id}
      - --fqdn-template={{.Name}}.${local.domain}
  EOF
  ]

  dynamic "set" {
    for_each = {
      "rbac.create"           = false
      "serviceAccount.create" = false
      "serviceAccount.name"   = kubernetes_service_account.external_dns.metadata.0.name
      "provider"              = "aws"
      "policy"                = "sync"
      "logLevel"              = "info"
      "sources"               = "{ingress}"
      "txtPrefix"             = "edns-"
    }
    content {
      name  = set.key
      value = set.value
    }
  }
  depends_on = [
    null_resource.cluster-functional
  ]
}
