locals {
  cluster_name    = "k8s-${substr(sha256(var.instance_name), 0, 16)}"
  cluster_version = "1.19"
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  # module versions above 14.0.0 do not work with Terraform 0.12, so we're stuck
  # on that version until the cloud-service-broker can use newer versions of
  # Terraform.
  version                       = "~>14.0"
  cluster_name                  = local.cluster_name
  cluster_version               = local.cluster_version
  vpc_id                        = module.vpc.aws_vpc_id
  subnets                       = module.vpc.aws_subnet_private_prod_ids
  cluster_enabled_log_types     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_log_retention_in_days = 180
  manage_aws_auth               = false
  write_kubeconfig              = false
  tags                          = merge(var.labels, { "domain" = local.domain })
  iam_path                      = "/${replace(local.cluster_name, "-", "")}/"
  fargate_profiles = {
    default = {
      name = "default"
      namespace = "default"
    }
    kubesystem = {
      name = "kube-system"
      namespace = "kube-system"
    }
  }
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

  # This depends_on ensures that this resource is not provisioned until the
  # cluster's kube API is available, and not until we've verified that
  # prerequisite binaries are available.
  depends_on = [
    null_resource.prerequisite_binaries_present,
    module.eks.cluster_id
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

