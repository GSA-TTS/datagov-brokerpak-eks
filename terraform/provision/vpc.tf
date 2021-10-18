locals {
  region = var.region
}

module "vpc" {
  source = "github.com/FairwindsOps/terraform-vpc.git?ref=v5.0.1"

  aws_region           = local.region
  az_count             = 2
  aws_azs              = "${local.region}b, ${local.region}c"
  single_nat_gateway   = 1
  multi_az_nat_gateway = 0

  enable_s3_vpc_endpoint = "true"

  # Tag subnets for use by AWS' load-balancers and the ALB ingress controllers
  # See https://aws.amazon.com/premiumsupport/knowledge-center/eks-vpc-subnet-discovery/
  global_tags = merge(var.labels, {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared",
    "domain"                                      = local.domain
  })
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_prod_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

resource "aws_security_group" "default_deny" {
  name        = "default_deny"
  description = "Set up default deny framework"

  ingress = [
    {
      self = null
      prefix_list_ids = null
      description = "Default Deny Ingress"
      security_groups = null
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/32"]
      ipv6_cidr_blocks = ["::/128"]
    }
  ]

  egress = [
    {
      self = null
      prefix_list_ids = null
      description = "Default Deny Egress"
      security_groups = null
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/32"]
      ipv6_cidr_blocks = ["::/128"]
    }
  ]

  tags = {
    Name = "default_deny"
  }
}
