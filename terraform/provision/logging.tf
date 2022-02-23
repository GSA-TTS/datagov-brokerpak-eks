# -----------------------------------------------------------------------------------
# Fargate Logging Policy and Policy Attachment for the existing Fargate pod execution IAM role
# -----------------------------------------------------------------------------------
resource "aws_iam_policy" "AmazonEKSFargateLoggingPolicy" {
  name   = "AmazonEKSFargateLoggingPolicy-${local.cluster_name}"
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

resource "aws_iam_role_policy_attachment" "AmazonEKSFargateLoggingPolicy" {
  policy_arn = aws_iam_policy.AmazonEKSFargateLoggingPolicy.arn
  role       = aws_iam_role.iam_role_fargate.name
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
    namespace = "aws-observability"
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
