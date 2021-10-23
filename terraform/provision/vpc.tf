locals {
  region = var.region
  domain_ip_file = "${path.module}/domain_ip"
}

# Look up the dns records for the eks control plane
# Docs: https://registry.terraform.io/providers/hashicorp/dns/latest/docs/resources/dns_a_record_set
data "dns_a_record_set" "cluster-control-plane" {
  host = replace(module.eks.cluster_endpoint, "https://", "")
}

# Create a route53 dns resolver for private subnet
# Docs: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint
resource "aws_route53_resolver_endpoint" "cluster-dns-out" {
  name      = "cluster-dns"
  direction = "OUTBOUND"

	security_group_ids = [
    module.vpc.default_security_group_id,
  ]

  ip_address {
  	subnet_id = module.vpc.private_subnets[0]
  }
  ip_address {
  	subnet_id = module.vpc.private_subnets[1]
  }
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

  map_public_ip_on_launch = false
  private_dedicated_network_acl = true
	enable_dns_hostnames = true
	enable_dns_support = true

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

  # By default, only communication with the control plane and dns servers should be allowed
  # https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html#cluster-sg
  default_security_group_egress = [
    {
      "description"      = "Allow Control Plane Traffic"
      "prefix_list_ids"  = null
      "security_groups"  = null
      "self"             = true
      "from_port"        = 0
      "to_port"          = 443
      "protocol"         = "tcp"
      "cidr_blocks"      = "0.0.0.0/0"
      "ipv6_cidr_blocks" = "::/0"
    },
    {
      "description"      = "Allow DNS"
      "prefix_list_ids"  = null
      "security_groups"  = null
      "self"             = true
      "from_port"        = 0
      "to_port"          = 53
      "protocol"         = "-1"
      "cidr_blocks"      = "0.0.0.0/0"
      "ipv6_cidr_blocks" = "::/0"
    },
  ]
  # Private subnets are not publicly accessible, so no need to restrict ingress traffic here
  default_security_group_ingress = [
    {
      "description"      = "Allow all ingress traffic"
      "prefix_list_ids"  = null
      "security_groups"  = null
      "self"             = true
      "from_port"        = 0
      "to_port"          = 0
      "protocol"         = "-1"
      "cidr_blocks"      = "0.0.0.0/0"
      "ipv6_cidr_blocks" = "::/0"
    }
  ]

  # All all inbound traffic to private subnets for now, user-defined cidrs may be specified later
  private_inbound_acl_rules = [
	  {
	    "cidr_block": "0.0.0.0/0",
	    "from_port": 0,
	    "protocol": "-1",
	    "rule_action": "allow",
	    "rule_number": 50,
	    "to_port": 0
	  }
  ]

  # Only allow private subnets to initiate communicate with,
  # - Other private subnets
  # - DNS
  # - EKS Control Plane
  # - Deny all others
  private_outbound_acl_rules = [
	  {
	    "cidr_block": "10.20.1.0/24",
	    "from_port": 0,
	    "protocol": "-1",
	    "rule_action": "allow",
	    "rule_number": 50,
	    "to_port": 0
	  },
	  {
	    "cidr_block": "10.20.2.0/24",
	    "from_port": 0,
	    "protocol": "-1",
	    "rule_action": "allow",
	    "rule_number": 51,
	    "to_port": 0
	  },
	  {
	    "cidr_block": "0.0.0.0/0",
	    "from_port": 0,
	    "protocol": "-1",
	    "rule_action": "allow",
	    "rule_number": 53,
	    "to_port": 53
	  },
	  {
      "cidr_block": format("%s/32", data.dns_a_record_set.cluster-control-plane.addrs[0]),
	    "from_port": 0,
	    "protocol": "-1",
	    "rule_action": "allow",
	    "rule_number": 54,
	    "to_port": 443
	  },
	  {
	    "cidr_block": "0.0.0.0/0",
	    "from_port": 0,
	    "protocol": "-1",
	    "rule_action": "deny",
	    "rule_number": 60,
	    "to_port": 0
	  }
  ]

  # This may not be necessary, but allow public subnets to i
  public_outbound_acl_rules = [
	  {
	    "cidr_block": "0.0.0.0/0",
	    "from_port": 0,
	    "protocol": "-1",
	    "rule_action": "allow",
	    "rule_number": 52,
	    "to_port": 53
	  },
	  {
	    "cidr_block": "0.0.0.0/0",
	    "from_port": 0,
	    "protocol": "-1",
	    "rule_action": "allow",
	    "rule_number": 52,
	    "to_port": 0
	  },
  ]
}

# Create VPC Endpoints for private subnets to connect to the following services,
# - S3 (for pulling images)
# - EC2
# - ECR API
# - ECR DKR
# - LOGS (for CloudWatch Logs)
# - STS (for IAM role access)
# - ELASTICLOADBALANCING (for Application Load Balancers)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = format("com.amazonaws.%s.s3", local.region)
}

resource "aws_vpc_endpoint" "ec2" {
  vpc_id       = module.vpc.vpc_id
  service_name = format("com.amazonaws.%s.ec2", local.region)
  vpc_endpoint_type = "Interface"
	security_group_ids = [
    module.vpc.default_security_group_id,
  ]
  subnet_ids = module.vpc.private_subnets
	private_dns_enabled = true
}

resource "aws_vpc_endpoint" "api" {
  vpc_id       = module.vpc.vpc_id
  service_name = format("com.amazonaws.%s.ecr.api", local.region)
  vpc_endpoint_type = "Interface"
	security_group_ids = [
    module.vpc.default_security_group_id,
  ]
  subnet_ids = module.vpc.private_subnets
	private_dns_enabled = true
}

resource "aws_vpc_endpoint" "dkr" {
  vpc_id       = module.vpc.vpc_id
  service_name = format("com.amazonaws.%s.ecr.dkr", local.region)
  vpc_endpoint_type = "Interface"
	security_group_ids = [
    module.vpc.default_security_group_id,
  ]
  subnet_ids = module.vpc.private_subnets
	private_dns_enabled = true
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id       = module.vpc.vpc_id
  service_name = format("com.amazonaws.%s.logs", local.region)
  vpc_endpoint_type = "Interface"
	security_group_ids = [
    module.vpc.default_security_group_id,
  ]
  subnet_ids = module.vpc.private_subnets
	private_dns_enabled = true
}

resource "aws_vpc_endpoint" "elb" {
  vpc_id       = module.vpc.vpc_id
  service_name = format("com.amazonaws.%s.elasticloadbalancing", local.region)
  vpc_endpoint_type = "Interface"
	security_group_ids = [
    module.vpc.default_security_group_id,
  ]
  subnet_ids = module.vpc.private_subnets
	private_dns_enabled = true
}

resource "aws_vpc_endpoint" "iam" {
  vpc_id       = module.vpc.vpc_id
  service_name = format("com.amazonaws.%s.sts", local.region)
  vpc_endpoint_type = "Interface"
	security_group_ids = [
    module.vpc.default_security_group_id,
  ]
  subnet_ids = module.vpc.private_subnets
	private_dns_enabled = true
}
