# Modeled after an example here:
# https://tech.polyconseil.fr/external-dns-helm-terraform.html

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "external_dns" {
  name               = "${local.cluster_name}-external-dns"
  tags               = var.labels
  assume_role_policy = <<-EOF
    {
    "Version": "2012-10-17",
    "Statement": [
        {
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Effect": "Allow",
        "Principal": {
            "Federated": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${module.eks.oidc_provider}"
        },
        "Condition": {
            "StringEquals": {
            "${module.eks.oidc_provider}:sub": "system:serviceaccount:kube-system:external-dns"
            }
        }
        }
    ]
    }
    EOF
}

resource "aws_iam_role_policy" "external_dns" {
  name_prefix = "${local.cluster_name}-external-dns"
  role        = aws_iam_role.external_dns.name
  policy      = <<-EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "route53:ChangeResourceRecordSets"
                ],
                "Resource": [
                    "arn:aws:route53:::hostedzone/${aws_route53_zone.cluster.zone_id}"
                ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "route53:ListHostedZones",
                    "route53:ListResourceRecordSets"
                ],
                "Resource": [
                    "*"
                ]
            }
        ]
    }
    EOF
}

resource "kubernetes_service_account" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn
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
        value: ${data.aws_region.current.name}
    extraArgs:
      - --zone-id-filter=${aws_route53_zone.cluster.zone_id}
      - --zone-name-filter=${local.domain}
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
}
