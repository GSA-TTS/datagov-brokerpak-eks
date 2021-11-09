locals {
  region = var.region
  domain_ip_file = "${path.module}/domain_ip"
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
	cidr = "10.20.0.0/16"
  private_subnets = ["10.20.1.0/24", "10.20.2.0/24"]
  public_subnets = ["10.20.101.0/24", "10.20.102.0/24"]

  azs              = ["${local.region}b", "${local.region}c"]
	enable_nat_gateway   = true
  single_nat_gateway   = true
  # enable_vpn_gateway   = true

	enable_dns_hostnames = true
	enable_dns_support = true

  # PRIVATE: test
  # map_public_ip_on_launch = false
  # private_dedicated_network_acl = true
  # default_security_group_egress = []

  # Tag subnets for use by AWS' load-balancers and the ALB ingress controllers
  # See https://aws.amazon.com/premiumsupport/knowledge-center/eks-vpc-subnet-discovery/
  tags = merge(var.labels, {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared",
    "domain"                                      = local.domain
  })
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

}

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
#   service_name = format("com.amazonaws.%s.s3.602401143452", local.region)
# }
# 
# resource "aws_vpc_endpoint" "ec2" {
#   vpc_id       = module.vpc.vpc_id
#   service_name = format("com.amazonaws.%s.ec2.602401143452", local.region)
#   vpc_endpoint_type = "Interface"
# 	security_group_ids = [
#     module.vpc.default_security_group_id,
#   ]
#   subnet_ids = flatten([module.vpc.private_subnets, module.vpc.public_subnets])
# 	private_dns_enabled = true
# }
# 
# resource "aws_vpc_endpoint" "api" {
#   vpc_id       = module.vpc.vpc_id
#   service_name = format("com.amazonaws.%s.ecr.api.602401143452", local.region)
#   vpc_endpoint_type = "Interface"
# 	security_group_ids = [
#     module.vpc.default_security_group_id,
#   ]
#   subnet_ids = flatten([module.vpc.private_subnets, module.vpc.public_subnets])
# 	private_dns_enabled = true
# }
# 
# resource "aws_vpc_endpoint" "dkr" {
#   vpc_id       = module.vpc.vpc_id
#   service_name = format("com.amazonaws.%s.ecr.dkr.602401143452", local.region)
#   vpc_endpoint_type = "Interface"
# 	security_group_ids = [
#     module.vpc.default_security_group_id,
#   ]
#   subnet_ids = flatten([module.vpc.private_subnets, module.vpc.public_subnets])
# 	private_dns_enabled = true
# }
# 
# resource "aws_vpc_endpoint" "logs" {
#   vpc_id       = module.vpc.vpc_id
#   service_name = format("com.amazonaws.%s.logs.602401143452", local.region)
#   vpc_endpoint_type = "Interface"
# 	security_group_ids = [
#     module.vpc.default_security_group_id,
#   ]
#   subnet_ids = flatten([module.vpc.private_subnets, module.vpc.public_subnets])
# 	private_dns_enabled = true
# }
# 
# resource "aws_vpc_endpoint" "elb" {
#   vpc_id       = module.vpc.vpc_id
#   service_name = format("com.amazonaws.%s.elasticloadbalancing.602401143452", local.region)
#   vpc_endpoint_type = "Interface"
# 	security_group_ids = [
#     module.vpc.default_security_group_id,
#   ]
#   subnet_ids = flatten([module.vpc.private_subnets, module.vpc.public_subnets])
# 	private_dns_enabled = true
# }
# 
# resource "aws_vpc_endpoint" "iam" {
#   vpc_id       = module.vpc.vpc_id
#   service_name = format("com.amazonaws.%s.sts.602401143452", local.region)
#   vpc_endpoint_type = "Interface"
# 	security_group_ids = [
#     module.vpc.default_security_group_id,
#   ]
#   subnet_ids = flatten([module.vpc.private_subnets, module.vpc.public_subnets])
# 	private_dns_enabled = true
# }
