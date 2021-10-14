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
# Fargate logging by fluentbit requires namespace aws-observability and Configmap
# ---------------------------------------------------------------------------------------------

# Configure Kubernetes namespace aws-observability by adding the aws-observability annotation. This
# annotation is supported in terraform 0.13 or higher. So kubectl is used to provision the namespace.
data "template_file" "logging" {
  template = <<-EOF
    kind: Namespace
    apiVersion: v1
    metadata:
      name: aws-observability
      labels:
        aws-observability: enabled
    ---
    kind: ConfigMap
    apiVersion: v1
    metadata:
      name: aws-logging
      namespace: aws-observability
    data:
      output.conf: |
        [OUTPUT]
          Name cloudwatch_logs
          Match   *
          region ${local.region}
          log_group_name fluent-bit-cloudwatch-${local.cluster_name}
          log_stream_prefix from-fluent-bit-
          auto_create_group On
  EOF
}

resource "null_resource" "namespace_fargate_logging" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(module.eks.kubeconfig)
    }
    command = <<-EOF
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) apply -f <(echo '${data.template_file.logging.rendered}') 
    EOF
  }
  depends_on = [
    null_resource.cluster-functional,
  ]
}
