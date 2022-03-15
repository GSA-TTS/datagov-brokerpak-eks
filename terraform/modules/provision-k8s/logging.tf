# ---------------------------------------------------------------------------------------------
# Logging by fluentbit requires namespace aws-observability and a configmap in Kubernetes
# ---------------------------------------------------------------------------------------------

# Configure Kubernetes namespace aws-observability with the aws-observability annotation.
resource "kubernetes_namespace" "logging" {
  metadata {
    name = "aws-observability"
    labels = {
      aws-observability = "enabled"
    }
  }
}
resource "kubernetes_config_map" "logging" {
  metadata {
    name      = "aws-logging"
    namespace = kubernetes_namespace.logging.metadata[0].name
  }

  data = {
    "output.conf" = <<-OUTPUTCONF
      [OUTPUT]
        Name cloudwatch_logs
        Match   *
        region ${local.region}
        log_group_name fluent-bit-cloudwatch-${local.cluster_name}
        log_stream_prefix from-fluent-bit-
        auto_create_group true
    OUTPUTCONF
  }
}
