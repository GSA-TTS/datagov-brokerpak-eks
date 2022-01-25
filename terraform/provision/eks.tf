locals {
  # Prevent provisioning if the necessary CLI binaries aren't present
  cluster_name    = "k8s-${substr(sha256(var.instance_name), 0, 16)}"
  cluster_version = "1.19"
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  # module versions above 14.0.0 do not work with Terraform 0.12, so we're stuck
  # on that version until the cloud-service-broker can use newer versions of
  # Terraform.
  version                           = "~>14.0"
  cluster_name                      = local.cluster_name
  cluster_version                   = local.cluster_version
  vpc_id                            = module.vpc.aws_vpc_id
  subnets                           = module.vpc.aws_subnet_private_prod_ids
  cluster_enabled_log_types         = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_log_retention_in_days     = 180
  manage_aws_auth                   = false
  write_kubeconfig                  = var.write_kubeconfig
  tags                              = merge(var.labels, { "domain" = local.domain })
  create_fargate_pod_execution_role = false
  # fargate_pod_execution_role_name = aws_iam_role.iam_role_fargate.name
  # fargate_profiles = {
  #   default = {
  #     name      = "default"
  #     namespace = "default"
  #   }
  #   kubesystem = {
  #     name      = "kube-system"
  #     namespace = "kube-system"
  #   }
  # }
  node_groups = {
    system_node_group = {
      name = "test"

      min_capacity = 1

      instance_types = ["m5.large"]
      capacity_type  = "ON_DEMAND"
    }
  }
}

resource "aws_iam_role" "iam_role_fargate" {
  name = "eks-fargate-profile-${local.cluster_name}"
  tags = var.labels
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


# We create Fargate profile(s) that select the requested
# namespace(s). Fargate profiles are expensive to create and destroy, and there
# can only be one create or destroy operation in flight at a time. So we want to
# create as few as possible, and do it sequentially rather than in parallel.
resource "aws_eks_fargate_profile" "default_namespaces" {
  cluster_name           = local.cluster_name
  fargate_profile_name   = "default-namespaces-${local.cluster_name}"
  pod_execution_role_arn = aws_iam_role.iam_role_fargate.arn
  subnet_ids             = module.vpc.aws_subnet_private_prod_ids
  tags                   = var.labels
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

  # This depends_on ensures that this resource is not provisioned until the
  # cluster's kube API is available.
  depends_on = [module.eks.cluster_id]
}

# Per AWS docs, for a Fargate-only cluster, you have to patch the coredns
# deployment to remove the constraint that it wants to run on ec2, then restart
# it so it will come up on Fargate.
resource "null_resource" "cluster-functional" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(module.eks.kubeconfig)
    }

    # Note the "rollout status" command blocks until the "rollout restart" is
    # complete. We do this intentionally because the cluster basically isn't
    # functional until coredns is operating (for example, helm deployments may
    # timeout). When another resource depends_on this one, it won't apply until
    # the cluster is fully functional.
    command = <<-EOF
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) \
        patch deployment coredns \
        --namespace kube-system \
        --type=json \
        -p='[{"op": "remove", "path": "/spec/template/metadata/annotations", "value": "eks.amazonaws.com/compute-type"}]' && \
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) rollout restart -n kube-system deployment coredns && \
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) rollout status -n kube-system deployment coredns
    EOF
  }
  # This depends_on ensures that coredns will not be patched and restarted until the
  # FargateProfile is in place, we've verified that prerequisite
  # binaries are available.
  depends_on = [
    null_resource.prerequisite_binaries_present,
    aws_eks_fargate_profile.default_namespaces,
  ]
}

# Resources referring to cluster attributes should make use of these 
# data sources so the cluster will be up and ready first
data "aws_eks_cluster" "main" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_id
}

# EBS CSI addon for Solr
resource "aws_eks_addon" "ebs-csi" {
  cluster_name = module.eks.cluster_id
  addon_name   = "aws-ebs-csi-driver"
}

resource "aws_iam_role_policy" "ebs-policy" {
  name_prefix = "${local.cluster_name}-ebs-policy"
  role        = aws_iam_role.iam_role_fargate.name
  policy      = local.ebs_policy
}
