output "server" { value = data.aws_eks_cluster.cluster.endpoint }
output "cluster_ca_certificate" { value = data.aws_eks_cluster.cluster.certificate_authority.0.data }
output "token" { value = data.aws_eks_cluster_auth.cluster.token }

locals {

  region = "us-east-1"

  # Options are [default|staging]
  # env = "${terraform.workspace}"
  env = "staging"

  cluster_name_map = {
    default = "datagov-k8s"
    staging = "datagov-k8s-staging"
  }

  cluster_name = "${lookup(local.cluster_name_map, local.env)}"

  vpc_cidr_map = {
    default = "10.0.0.0/16"
    staging = "172.16.0.0/16"
  }

  vpc_cidr = "${lookup(local.vpc_cidr_map, local.env)}"


  vpc_subnets_map = {
    default = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
    staging  = "${cidrsubnets(local.vpc_cidr,4 ,4 ,4 )}"
  }
 
  vpc_subnets= "${lookup(local.vpc_subnets_map, local.env)}"

  base_domain_map = {
    default = "logtimegames.com"
    staging = "staging.logtimegames.com"
  }
  base_domain = "${lookup(local.base_domain_map, local.env)}"
}

provider "aws" {
  region = local.region
  profile = "terraform-operator"
  version = "~> 2.67"
}

data "aws_availability_zones" "available" {
  
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.44.0"
  name = "vpc-${local.cluster_name}"
  cidr = "${local.vpc_cidr}" # 192.168 , 172.16
  azs = data.aws_availability_zones.available.names
  public_subnets = "${local.vpc_subnets}"

  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

}

resource "aws_iam_policy" "autoscaler_policy" {
  name        = "autoscaler"
  path        = "/"
  description = "Autoscaler bots are fully allowed to read/run autoscaling groups"
 
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
    "Action": [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeLaunchTemplateVersions"
    ],
    "Resource": "*",
    "Effect": "Allow"
    }
  ]
}
EOF
}

# static config of k8s provider - TMP
# provider "kubernetes" {
#   host = module.eks.cluster_endpoint
#   load_config_file = true
#   # kubeconfig file relative to path where you execute tf, in my case it is the same dir
#   config_path      = "kubeconfig_${local.cluster_name}"
#   version = "~> 1.9"
# }


data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

# dynamic 
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "~> 1.11.1"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "12.1.0"
  # insert the 4 required variables here
  cluster_name = "${local.cluster_name}"
  cluster_version = "1.16"
  subnets = module.vpc.public_subnets
  vpc_id = module.vpc.vpc_id
  # map_users = var.map_users
  # worker nodes
  worker_groups_launch_template = [
    {
      name                 = "worker-group-1"
      instance_type        = "t3.large"
      asg_desired_capacity = 2
      asg_max_size = 5
      asg_min_size  = 2
      autoscaling_enabled = true
      public_ip            = true
      tag_specifications = {
        resource_type = "instance"
        tags = {
          Name = "k8s.io/cluster-autoscaler/${local.cluster_name}"
        }
      }

      tag_specifications = {
        resource_type = "instance"
        tags = {
          Name = "k8s.io/cluster-autoscaler/enabled"
        }
      }
    }
  ]
  # for cluster-autoscaler (page 153 https://docs.aws.amazon.com/eks/latest/userguide/eks-ug.pdf)
  workers_additional_policies = [
    aws_iam_policy.autoscaler_policy.arn
  ]

}

# Explicitly create namespaces
resource "kubernetes_namespace" "apps" {
  metadata {
    name = "apps"
  }
  depends_on = [
    module.eks.cluster_id
  ]
}

resource "kubernetes_namespace" "monitoring" {
  count = local.env == "default" ? 1 : 0
  metadata {
    name = "monitoring"
  }
  depends_on = [
    module.eks.cluster_id
  ]
}
