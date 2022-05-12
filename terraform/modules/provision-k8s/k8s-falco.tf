# Creating namespace for falco.
# So that the default-deny-egress network policy does not affect falco pods.
resource "kubernetes_namespace" "falco" {
  metadata {
    name = "falco"
  }
}

resource "helm_release" "falco" {
  name       = "falco"
  chart      = "falco"
  repository = "https://falcosecurity.github.io/charts"
  version    = "1.18.3"

  namespace       = kubernetes_namespace.falco.metadata[0].name
  cleanup_on_fail = "true"
  timeout         = 600

  dynamic "set" {
    for_each = {
      "falcosidekick.enabled"                      = true,
      "falcosidekick.config.slack.webhookurl"      = var.slack_webhookurl,
      "falcosidekick.config.slack.minimumpriority" = "warning",
    }
    content {
      name  = set.key
      value = set.value
    }
  }
}