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

resource "aws_default_security_group" "default" {
  vpc_id = module.vpc.aws_vpc_id

  ingress = [
    {
      cidr_blocks      = null
      description      = "Allow all ingress traffic"
      ipv6_cidr_blocks = null
      prefix_list_ids  = null
      security_groups  = null
      protocol         = -1
      self             = true
      from_port        = 0
      to_port          = 0
    }
  ]

  // By not defining egress, this revokes all authorization for egress traffic
  // for the default security group.  Other security groups may still allow egress
  // traffic.
}

data "aws_network_acls" "default_acl" {
  vpc_id = module.vpc.aws_vpc_id
}

resource "aws_network_acl_rule" "allow_input_egress" {
  count          = (var.egress_allowed != null ? length(var.egress_allowed) : 0)
  network_acl_id = tolist(data.aws_network_acls.default_acl.ids)[0]
  rule_number    = count.index + 2
  egress         = true
  protocol       = "all"
  rule_action    = "allow"
  cidr_block     = var.egress_allowed[count.index]
  from_port      = null
  to_port        = null

  depends_on = [
    null_resource.cluster-functional,
  ]
}

resource "aws_network_acl_rule" "allow_input_ingress" {
  count          = (var.ingress_allowed != null ? length(var.ingress_allowed) : 0)
  network_acl_id = tolist(data.aws_network_acls.default_acl.ids)[0]
  rule_number    = count.index + 2
  egress         = false
  protocol       = "all"
  rule_action    = "allow"
  cidr_block     = var.ingress_allowed[count.index]
  from_port      = null
  to_port        = null

  depends_on = [
    null_resource.cluster-functional,
  ]
}

resource "aws_network_acl_rule" "deny_remaining_egress" {
  count          = (var.egress_allowed != null ? 1 : 0)
  network_acl_id = tolist(data.aws_network_acls.default_acl.ids)[0]
  rule_number    = length(var.egress_allowed) + 2
  egress         = true
  protocol       = "all"
  rule_action    = "deny"
  cidr_block     = "0.0.0.0/0"
  from_port      = null
  to_port        = null

  depends_on = [
    null_resource.cluster-functional,
  ]
}

resource "aws_network_acl_rule" "deny_remaining_ingress" {
  count          = (var.ingress_allowed != null ? 1 : 0)
  network_acl_id = tolist(data.aws_network_acls.default_acl.ids)[0]
  rule_number    = length(var.ingress_allowed) + 2
  egress         = false
  protocol       = "all"
  rule_action    = "deny"
  cidr_block     = "0.0.0.0/0"
  from_port      = null
  to_port        = null

  depends_on = [
    null_resource.cluster-functional,
  ]
}
