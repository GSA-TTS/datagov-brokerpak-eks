locals {
  region = var.region
}

data "aws_availability_zones" "available" {
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.11.4"
  # insert the 23 required variables here
  name = "eks-vpc"
  cidr = "10.31.0.0/16"

  azs             = data.aws_availability_zones.available.names
  private_subnets = ["10.31.1.0/24", "10.31.2.0/24", "10.31.3.0/24"]
  public_subnets  = ["10.31.101.0/24", "10.31.102.0/24", "10.31.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true

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

