
# data "aws_iam_policy" "ssm_managed_instance" {
#   arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
# }
# 
# resource "aws_iam_role_policy_attachment" "karpenter_ssm_policy" {
#   role       = module.eks.cluster_iam_role_name
#   policy_arn = data.aws_iam_policy.ssm_managed_instance.arn
# }
# 
resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile-${local.cluster_name}"
  role = module.eks.cluster_iam_role_name
}
# 
module "iam_assumable_role_karpenter" {
  source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                       = "5.30.0"
  create_role                   = true
  role_name                     = "karpenter-controller-${local.cluster_name}"
  provider_url                  = module.eks.cluster_oidc_issuer_url
  oidc_fully_qualified_subjects = ["system:serviceaccount:karpenter:karpenter"]
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name = "karpenter-policy-${local.cluster_name}"
  role = module.iam_assumable_role_karpenter.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:CreateTags",
          "iam:PassRole",
          "ec2:TerminateInstances",
          "ec2:DescribeLaunchTemplates",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ssm:GetParameter"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "https://charts.karpenter.sh"
  chart      = "karpenter"
  version    = "v0.9.1"

  dynamic "set" {
    for_each = {
      "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn" = module.iam_assumable_role_karpenter.iam_role_arn,
      "clusterName"                                               = local.cluster_name,
      "clusterEndpoint"                                           = module.eks.cluster_endpoint,
      "aws.defaultInstanceProfile"                                = aws_iam_instance_profile.karpenter.name
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

# data "aws_launch_template" "eks_launch_template" {
#   id = module.eks.eks_managed_node_groups["system"].launch_template_id
# }
# data "aws_ami" "gsa-ise" {
#   count       = var.use_hardened_ami ? 1 : 0
#   owners      = ["self", "752281881774", "821341638715"]
#   most_recent = true
#   filter {
#     name   = "name"
#     values = ["ISE-AMZ-LINUX-EKS-v1.21-GSA-HARDENED*"]
#   }
# }
