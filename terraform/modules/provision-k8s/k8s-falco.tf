resource "helm_release" "falco" {
  name       = "falco"
  chart      = "falco"
  repository = "https://falcosecurity.github.io/charts"
  version    = "1.18.3"

  namespace       = "default"
  cleanup_on_fail = "true"
  timeout = 600

  dynamic "set" {
    for_each = {
      "falcosidekick.enabled"                = true,
      "falcosidekick.config.slack.webhookurl" = var.slack_webhookurl,
    }
    content {
      name  = set.key
      value = set.value
    }
  }
}