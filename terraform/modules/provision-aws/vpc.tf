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
  # These subnets represent AZs us-west-2a, us-west-2b, and us-west-2c
  # This gives us 8187 IP addresses that can be given to nodes and (via the VPC-CNI add-on) pods.
  private_subnets = ["10.31.0.0/19", "10.31.32.0/19", "10.31.64.0/19", "10.31.96.0/19"]
  public_subnets  = ["10.31.128.0/19", "10.31.160.0/19", "10.31.192.0/19", "10.31.224.0/19"]

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

