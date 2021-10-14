# This Terraform code will create an AWS user named "ssb-eks-broker" with the
# minimum policies in place that are needed for this brokerpak to operate. 


locals {
  this_aws_account_id    = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {}

module "ssb-eks-broker-user" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-user"
  version = "~> 4.2.0"

  create_iam_user_login_profile = false
  force_destroy                 = true
  name                          = "ssb-eks-broker"
}

resource "aws_iam_user_policy_attachment" "eks_broker_policies" {
  for_each = toset([
    // ACM manager: for aws_acm_certificate, aws_acm_certificate_validation
    "arn:aws:iam::aws:policy/AWSCertificateManagerFullAccess",

    // EKS manager: for aws_eks_cluster
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",

    // Route53 manager: for aws_route53_record, aws_route53_zone
    "arn:aws:iam::aws:policy/AmazonRoute53FullAccess",

    // WAF2: for aws_wafv2_web_acl
    "arn:aws:iam::aws:policy/AWSWAFFullAccess",

    // AWS EKS module policy defined below
    "arn:aws:iam::${local.this_aws_account_id}:policy/${module.eks_module_policy.name}",

    // AWS EKS brokerpak policy defined below
    "arn:aws:iam::${local.this_aws_account_id}:policy/${module.eks_brokerpak_policy.name}",

    // Uncomment if we are still missing stuff and need to get it working again
    // "arn:aws:iam::aws:policy/AdministratorAccess"
  ])
  user       = module.ssb-eks-broker-user.iam_user_name
  policy_arn = each.key
}

module "eks_brokerpak_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "~> 4.2.0"

  name        = "eks_brokerpak_policy"
  path        = "/"
  description = "Policy granting additional permissions needed by the EKS brokerpak"
  policy      = <<-EOF
    {
      "Version": "2012-10-17",
      "Statement": [
          {
            "Effect": "Allow",
            "Action": [
              "ec2:DeleteVpcEndpoints"
            ],
            "Resource": "*"
          }
      ]
    }
  EOF
}


module "eks_module_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "~> 4.2.0"

  name        = "eks_module_policy"
  path        = "/"
  description = "Policy granting permissions needed by the AWS EKS Terraform module"

  # The policy content below comes from the URL below on 2021/08/09: 
  # https://github.com/terraform-aws-modules/terraform-aws-eks/blob/master/docs/iam-permissions.md
  policy = <<-EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "VisualEditor0",
                "Effect": "Allow",
                "Action": [
                    "autoscaling:AttachInstances",
                    "autoscaling:CreateAutoScalingGroup",
                    "autoscaling:CreateLaunchConfiguration",
                    "autoscaling:CreateOrUpdateTags",
                    "autoscaling:DeleteAutoScalingGroup",
                    "autoscaling:DeleteLaunchConfiguration",
                    "autoscaling:DeleteTags",
                    "autoscaling:Describe*",
                    "autoscaling:DetachInstances",
                    "autoscaling:SetDesiredCapacity",
                    "autoscaling:UpdateAutoScalingGroup",
                    "autoscaling:SuspendProcesses",
                    "ec2:AllocateAddress",
                    "ec2:AssignPrivateIpAddresses",
                    "ec2:Associate*",
                    "ec2:AttachInternetGateway",
                    "ec2:AttachNetworkInterface",
                    "ec2:AuthorizeSecurityGroupEgress",
                    "ec2:AuthorizeSecurityGroupIngress",
                    "ec2:CreateDefaultSubnet",
                    "ec2:CreateDhcpOptions",
                    "ec2:CreateEgressOnlyInternetGateway",
                    "ec2:CreateInternetGateway",
                    "ec2:CreateNatGateway",
                    "ec2:CreateNetworkInterface",
                    "ec2:CreateRoute",
                    "ec2:CreateRouteTable",
                    "ec2:CreateSecurityGroup",
                    "ec2:CreateSubnet",
                    "ec2:CreateTags",
                    "ec2:CreateVolume",
                    "ec2:CreateVpc",
                    "ec2:CreateVpcEndpoint",
                    "ec2:DeleteDhcpOptions",
                    "ec2:DeleteEgressOnlyInternetGateway",
                    "ec2:DeleteInternetGateway",
                    "ec2:DeleteNatGateway",
                    "ec2:DeleteNetworkInterface",
                    "ec2:DeleteRoute",
                    "ec2:DeleteRouteTable",
                    "ec2:DeleteSecurityGroup",
                    "ec2:DeleteSubnet",
                    "ec2:DeleteTags",
                    "ec2:DeleteVolume",
                    "ec2:DeleteVpc",
                    "ec2:DeleteVpnGateway",
                    "ec2:Describe*",
                    "ec2:DetachInternetGateway",
                    "ec2:DetachNetworkInterface",
                    "ec2:DetachVolume",
                    "ec2:Disassociate*",
                    "ec2:ModifySubnetAttribute",
                    "ec2:ModifyVpcAttribute",
                    "ec2:ModifyVpcEndpoint",
                    "ec2:ReleaseAddress",
                    "ec2:RevokeSecurityGroupEgress",
                    "ec2:RevokeSecurityGroupIngress",
                    "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
                    "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
                    "ec2:CreateLaunchTemplate",
                    "ec2:CreateLaunchTemplateVersion",
                    "ec2:DeleteLaunchTemplate",
                    "ec2:DeleteLaunchTemplateVersions",
                    "ec2:DescribeLaunchTemplates",
                    "ec2:DescribeLaunchTemplateVersions",
                    "ec2:GetLaunchTemplateData",
                    "ec2:ModifyLaunchTemplate",
                    "ec2:RunInstances",
                    "eks:CreateCluster",
                    "eks:DeleteCluster",
                    "eks:DescribeCluster",
                    "eks:ListClusters",
                    "eks:UpdateClusterConfig",
                    "eks:UpdateClusterVersion",
                    "eks:DescribeUpdate",
                    "eks:TagResource",
                    "eks:UntagResource",
                    "eks:ListTagsForResource",
                    "eks:CreateFargateProfile",
                    "eks:DeleteFargateProfile",
                    "eks:DescribeFargateProfile",
                    "eks:ListFargateProfiles",
                    "eks:CreateNodegroup",
                    "eks:DeleteNodegroup",
                    "eks:DescribeNodegroup",
                    "eks:ListNodegroups",
                    "eks:UpdateNodegroupConfig",
                    "eks:UpdateNodegroupVersion",
                    "iam:AddRoleToInstanceProfile",
                    "iam:AttachRolePolicy",
                    "iam:CreateInstanceProfile",
                    "iam:CreateOpenIDConnectProvider",
                    "iam:CreateServiceLinkedRole",
                    "iam:CreatePolicy",
                    "iam:CreatePolicyVersion",
                    "iam:CreateRole",
                    "iam:DeleteInstanceProfile",
                    "iam:DeleteOpenIDConnectProvider",
                    "iam:DeletePolicy",
                    "iam:DeletePolicyVersion",
                    "iam:DeleteRole",
                    "iam:DeleteRolePolicy",
                    "iam:DeleteServiceLinkedRole",
                    "iam:DetachRolePolicy",
                    "iam:GetInstanceProfile",
                    "iam:GetOpenIDConnectProvider",
                    "iam:GetPolicy",
                    "iam:GetPolicyVersion",
                    "iam:GetRole",
                    "iam:GetRolePolicy",
                    "iam:List*",
                    "iam:PassRole",
                    "iam:PutRolePolicy",
                    "iam:RemoveRoleFromInstanceProfile",
                    "iam:TagOpenIDConnectProvider",
                    "iam:TagRole",
                    "iam:UntagRole",
                    "iam:UpdateAssumeRolePolicy",
                    "logs:CreateLogGroup",
                    "logs:DescribeLogGroups",
                    "logs:DeleteLogGroup",
                    "logs:ListTagsLogGroup",
                    "logs:PutRetentionPolicy",
                    "kms:CreateAlias",
                    "kms:CreateGrant",
                    "kms:CreateKey",
                    "kms:DeleteAlias",
                    "kms:DescribeKey",
                    "kms:GetKeyPolicy",
                    "kms:GetKeyRotationStatus",
                    "kms:ListAliases",
                    "kms:ListResourceTags",
                    "kms:ScheduleKeyDeletion"
                ],
                "Resource": "*"
            }
        ]
    }
  EOF
}
