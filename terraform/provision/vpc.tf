locals {
  region         = var.region
  domain_ip_file = "${path.module}/domain_ip"
}

data "aws_availability_zones" "available" {
}

module "vpc" {
  # Version 3.8+ require Terraform 0.13+
  # Version 3.7+ require AWS 3.38+
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.6.0"

  name = "eks-vpc"
  # This cidr range was used by the old VPC module, it was kept for consistency
  # The accompanying subnets were choosen using tutorial as example
  # https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/3.7.0#usage
  cidr            = "10.20.0.0/16"
  private_subnets = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
  public_subnets  = ["10.20.101.0/24", "10.20.102.0/24", "10.20.103.0/24"]

  azs                = data.aws_availability_zones.available.names
  enable_nat_gateway = true
  single_nat_gateway = true
  enable_vpn_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tag subnets for use by AWS' load-balancers and the ALB ingress controllers
  # See https://aws.amazon.com/premiumsupport/knowledge-center/eks-vpc-subnet-discovery/
  tags = merge(var.labels, {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared",
    "domain"                                      = local.domain
  })
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }
  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }

}

# CNI addon for VPC
resource "aws_eks_addon" "cni" {
  cluster_name = module.eks.cluster_id
  addon_name   = "vpc-cni"
}

data "tls_certificate" "eks-cni" {
  url = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "cni_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-node"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
      type        = "Federated"
    }
  }
}

# THIS CAN PROBABLY BE DELETED SOON
# Create VPC Endpoints for private subnets to connect to the following services,
# - S3 (for pulling images)
# - EC2
# - ECR API
# - ECR DKR
# - LOGS (for CloudWatch Logs)
# - STS (for IAM role access)
# - ELASTICLOADBALANCING (for Application Load Balancers)
# resource "aws_vpc_endpoint" "s3" {
#   vpc_id       = module.vpc.vpc_id
#   service_name = format("com.amazonaws.%s.s3", local.region)
# }
# 
# resource "aws_vpc_endpoint" "ec2" {
#   vpc_id       = module.vpc.vpc_id
#   service_name = format("com.amazonaws.%s.ec2", local.region)
#   vpc_endpoint_type = "Interface"
# 	security_group_ids = [
#     module.vpc.default_security_group_id,
#   ]
#   # subnet_ids = flatten([module.vpc.private_subnets, module.vpc.public_subnets])
#   subnet_ids = module.vpc.private_subnets
# 	private_dns_enabled = true
# }
# 
# resource "aws_vpc_endpoint" "api" {
#   vpc_id       = module.vpc.vpc_id
#   service_name = format("com.amazonaws.%s.ecr.api", local.region)
#   vpc_endpoint_type = "Interface"
# 	security_group_ids = [
#     module.vpc.default_security_group_id,
#   ]
#   subnet_ids = module.vpc.private_subnets
# 	private_dns_enabled = true
# }
# 
# resource "aws_vpc_endpoint" "dkr" {
#   vpc_id       = module.vpc.vpc_id
#   service_name = format("com.amazonaws.%s.ecr.dkr", local.region)
#   vpc_endpoint_type = "Interface"
# 	security_group_ids = [
#     module.vpc.default_security_group_id,
#   ]
#   subnet_ids = module.vpc.private_subnets
# 	private_dns_enabled = true
# }
# 
# resource "aws_vpc_endpoint" "logs" {
#   vpc_id       = module.vpc.vpc_id
#   service_name = format("com.amazonaws.%s.logs", local.region)
#   vpc_endpoint_type = "Interface"
# 	security_group_ids = [
#     module.vpc.default_security_group_id,
#   ]
#   subnet_ids = module.vpc.private_subnets
# 	private_dns_enabled = true
# }
# 
# resource "aws_vpc_endpoint" "elb" {
#   vpc_id       = module.vpc.vpc_id
#   service_name = format("com.amazonaws.%s.elasticloadbalancing", local.region)
#   vpc_endpoint_type = "Interface"
# 	security_group_ids = [
#     module.vpc.default_security_group_id,
#   ]
#   subnet_ids = module.vpc.private_subnets
# 	private_dns_enabled = true
# }
# 
# resource "aws_vpc_endpoint" "iam" {
#   vpc_id       = module.vpc.vpc_id
#   service_name = format("com.amazonaws.%s.sts", local.region)
#   vpc_endpoint_type = "Interface"
# 	security_group_ids = [
#     module.vpc.default_security_group_id,
#   ]
#   subnet_ids = module.vpc.private_subnets
# 	private_dns_enabled = true
# }
