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
