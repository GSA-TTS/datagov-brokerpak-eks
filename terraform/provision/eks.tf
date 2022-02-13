locals {
  # Prevent provisioning if the necessary CLI binaries aren't present
  cluster_name    = "k8s-${substr(sha256(var.instance_name), 0, 16)}"
  cluster_version = "1.21"
  kubeconfig      = "kubeconfig-${local.cluster_name}"
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version                           = "~> 18.6"
  cluster_name                      = local.cluster_name
  cluster_version                   = local.cluster_version
  vpc_id                            = module.vpc.vpc_id
  subnet_ids                        = module.vpc.private_subnets
  cluster_enabled_log_types         = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days  = 180
  tags                              = merge(var.labels, { "domain" = local.domain })
  cluster_addons = {
    coredns = {
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {}

    # Necessary to support the AWS Load Balancer controller using NLBs. See:
    # https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.3/guide/service/nlb/#prerequisites
    vpc-cni = {
      resolve_conflicts = "OVERWRITE"
    }

    # Necessary to support Persistent Volume Claims (PVCs).
    aws-ebs-csi-driver = {
      resolve_conflicts = "OVERWRITE"
    }
  }
  
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

  eks_managed_node_groups = {
    system_node_group = {
      name = "eks-node-group"

      desired_capacity = var.mng_desired_capacity
      max_capacity     = var.mng_max_capacity
      min_capacity     = var.mng_min_capacity

      instance_types = var.mng_instance_types
      capacity_type  = "ON_DEMAND"
    }
  }
}

# Generate a kubeconfig file for use in provisioners
data "template_file" "kubeconfig" {
  template = <<-EOF
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

resource "local_file" "kubeconfig" {
  # Only create the file if requested; it's not needed by provisioners
  count = var.write_kubeconfig ? 1 : 0
  sensitive_content = data.template_file.kubeconfig.rendered
  filename = local.kubeconfig
  file_permission = "0600"
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
  count                  = 0
  cluster_name           = local.cluster_name
  fargate_profile_name   = "default-namespaces-${local.cluster_name}"
  pod_execution_role_arn = aws_iam_role.iam_role_fargate.arn
  subnet_ids             = module.vpc.private_subnets
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
      KUBECONFIG = base64encode(data.template_file.kubeconfig.rendered)
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
    module.eks.cluster_id,
    module.eks.aws_eks_node_group
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
