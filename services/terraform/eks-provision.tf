output "kubeconfig" { value = data.template_file.kubeconfig.rendered }

locals {
  cluster_name    = "k8s-${random_id.cluster.hex}"
  cluster_version = "1.18"
  region          = "us-east-1"
}
resource "random_id" "cluster" {
  byte_length = 8
}
provider "aws" {
  # We need at least 3.16.0 because it fixes a problem with creating/deleting
  # Fargate profiles in parallel. See this issue for more information:
  # https://github.com/hashicorp/terraform-provider-aws/issues/13372#issuecomment-729689441
  version = "~> 3.16.0"
  region  = local.region
}


module "vpc" {
  source = "github.com/FairwindsOps/terraform-vpc.git?ref=v5.0.1"

  aws_region           = local.region
  az_count             = 2
  aws_azs              = "us-east-1b, us-east-1c"
  single_nat_gateway   = 1
  multi_az_nat_gateway = 0

  enable_s3_vpc_endpoint = "true"

  # Tag subnets for use by AWS' load-balancers and the ALB ingress controllers
  # See https://aws.amazon.com/premiumsupport/knowledge-center/eks-vpc-subnet-discovery/
  global_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_prod_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "13.2.1"
  cluster_name    = local.cluster_name
  cluster_version = local.cluster_version
  vpc_id          = module.vpc.aws_vpc_id
  subnets         = module.vpc.aws_subnet_private_prod_ids

  # Look ma, no node_groups!
  # node_groups = {
  #   eks_nodes = {
  #     desired_capacity = 3
  #     max_capacity     = 3
  #     min_capacity     = 3
  #     instance_type = "t2.small"
  #   }
  # }
  manage_aws_auth = false
}

data "aws_eks_cluster" "main" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_id
}

resource "aws_iam_role" "iam_role_fargate" {
  name = "eks-fargate-profile"
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks-fargate-pods.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "AmazonEKSFargatePodExecutionRolePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.iam_role_fargate.name
}

resource "aws_eks_fargate_profile" "default_namespaces" {
  depends_on             = [module.eks]
  cluster_name           = data.aws_eks_cluster.main.name
  fargate_profile_name   = "default_namespaces"
  pod_execution_role_arn = aws_iam_role.iam_role_fargate.arn
  subnet_ids             = module.vpc.aws_subnet_private_prod_ids
  timeouts {
    # For reasons unknown, Fargate profiles can take upward of 20 minutes to
    # delete! I've never seen them go past 30m, though, so this seems OK.
    delete = "30m"
  }
  selector {
    namespace = "default"
  }
  selector {
    namespace = "kube-system"
  }
}

# Generate a kubeconfig file for use in provisioners and output
data "template_file" "kubeconfig" {
  template = <<EOF
apiVersion: v1
kind: Config
current-context: terraform
clusters:
- name: ${data.aws_eks_cluster.main.name}
  cluster:
    certificate-authority-data: ${data.aws_eks_cluster.main.certificate_authority.0.data}
    server: ${data.aws_eks_cluster.main.endpoint}
contexts:
- name: terraform
  context:
    cluster: ${data.aws_eks_cluster.main.name}
    user: terraform
users:
- name: terraform
  user:
    token: ${data.aws_eks_cluster_auth.main.token}
EOF
}

# Per AWS docs, you have to patch the coredns deployment to remove the
# constraint that it wants to run on ec2, then restart it. 
resource "null_resource" "coredns_patch" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOF
kubectl --kubeconfig=<(echo '${data.template_file.kubeconfig.rendered}') \
  patch deployment coredns \
  --namespace kube-system \
  --type=json \
  -p='[{"op": "remove", "path": "/spec/template/metadata/annotations", "value": "eks.amazonaws.com/compute-type"}]'
EOF
  }
}

resource "null_resource" "coredns_restart_on_fargate" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOF
kubectl --kubeconfig=<(echo '${data.template_file.kubeconfig.rendered}') rollout restart -n kube-system deployment coredns
EOF
  }
  depends_on = [
    null_resource.coredns_patch,
    aws_eks_fargate_profile.default_namespaces
  ]
}

# We need an OIDC provider for the ALB ingress controller to work
data "tls_certificate" "main" {
  url = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
}
resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.main.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
}

provider "kubernetes" {
  alias                  = "eks"
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
  load_config_file       = false
}

provider "helm" {
  alias = "eks"
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

data "aws_region" "current" {}

# Use a convenient module to install the AWS Load Balancer controller
module "aws_load_balancer_controller" {
  source = "github.com/mogul/terraform-kubernetes-aws-load-balancer-controller.git?ref=v4.0.0"
  providers = {
    kubernetes = kubernetes.eks,
    helm       = helm.eks
  }
  k8s_cluster_type          = "eks"
  k8s_namespace             = "kube-system"
  aws_region_name           = data.aws_region.current.name
  k8s_cluster_name          = data.aws_eks_cluster.main.name
  alb_controller_depends_on = [aws_eks_fargate_profile.default_namespaces]
}

