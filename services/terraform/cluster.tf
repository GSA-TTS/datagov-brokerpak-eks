output "kubeconfig" { value = data.template_file.kubeconfig.rendered }

locals {
  # TODO: Generate the cluster ID
  cluster_name = "main"
  cluster_version = "1.18"
  region = "us-east-1"
}

provider "aws" {
  # We need at least 3.16.0 because it fixes a problem with creating/deleting
  # Fargate profiles in parallel. See this issue for more information:
  # https://github.com/hashicorp/terraform-provider-aws/issues/13372#issuecomment-729689441
  version = "~> 3.16.0"
  region = local.region
}


module "vpc" {
  source = "git::ssh://git@github.com/FairwindsOps/terraform-vpc.git?ref=v5.0.1"

  aws_region = local.region
  az_count   = 3
  aws_azs    = "us-east-1a, us-east-1b, us-east-1c"

  global_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

module "eks" {
  source       = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=v13.2.1"
  cluster_name = local.cluster_name
  cluster_version = local.cluster_version
  vpc_id       = module.vpc.aws_vpc_id
  subnets      = module.vpc.aws_subnet_private_prod_ids

  # Look ma, no node_groups!
  # node_groups = {
  #   eks_nodes = {
  #     desired_capacity = 3
  #     max_capacity     = 3
  #     min_capaicty     = 3
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
  depends_on = [module.eks]
  cluster_name           = local.cluster_name
  fargate_profile_name   = "default_namespaces"
  pod_execution_role_arn = aws_iam_role.iam_role_fargate.arn
  subnet_ids             = module.vpc.aws_subnet_private_prod_ids
  timeouts {
    # For reasons unknown, Fargate profiles can take upward of 20 minutes to
    # delete! I've never seen them go past 30m, though, so this seems OK.
    delete                 = "30m"
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
- name: main
  cluster:
    certificate-authority-data: ${data.aws_eks_cluster.main.certificate_authority.0.data}
    server: ${data.aws_eks_cluster.main.endpoint}
contexts:
- name: terraform
  context:
    cluster: main
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

resource "null_resource" "coredns_restart" {
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
