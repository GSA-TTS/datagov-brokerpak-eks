# ---------------------------------------------
# Logging Policy for the pod execution IAM role
# ---------------------------------------------
resource "aws_iam_policy" "pod-logging" {
  name   = "${local.cluster_name}-pod-logging"
  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:CreateLogGroup",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }]
  }
  EOF
}

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
    name = "aws-logging"
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
