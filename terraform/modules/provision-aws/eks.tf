locals {
  cluster_name    = "k8s-${substr(sha256(var.instance_name), 0, 16)}"
  cluster_version = "1.28"
  kubeconfig_name = "kubeconfig-${local.cluster_name}"
}

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

module "eks" {
  source                                 = "terraform-aws-modules/eks/aws"
  version                                = "~> 19.17.2"
  cluster_name                           = local.cluster_name
  cluster_version                        = local.cluster_version
  vpc_id                                 = module.vpc.vpc_id
  subnet_ids                             = module.vpc.private_subnets
  cluster_enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = 180
  enable_irsa                            = true
  cluster_endpoint_private_access        = true
  cluster_endpoint_public_access         = true
  cluster_endpoint_public_access_cidrs = concat(
    var.control_plane_ingress_cidrs,        # User-specified IP
    ["${module.vpc.nat_public_ips[0]}/32"], # EKS Cluster Public IP
    ["${chomp(data.http.myip.body)}/32"]    # IP of machine executing terraform code
  )
  tags = merge(var.labels,
    { "domain" = local.domain },
    { "karpenter.sh/discovery" = local.cluster_name },
    { "k8s.io/cluster-autoscaler/enabled" = true },
    { "k8s.io/cluster-autoscaler/${local.cluster_name}" = local.cluster_name },
    { "autoDiscovery.clusterName" = local.cluster_name },
    { "awsRegion" = data.aws_region.current.name },
  )
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
    # TODO: since moving back to EFS, we don't need this.  However, if we
    # want to keep it around.  It should be configurable I suppose..
    aws-ebs-csi-driver = {
      resolve_conflicts = "OVERWRITE"
    }
  }

  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        {
          namespace = "kube-system"
        },
        {
          namespace = "default"
        }
      ]

      timeouts = {
        create = "20m"
        # For reasons unknown, Fargate profiles can take upward of 20 minutes to
        # delete! I've never seen them go past 30m, though, so this seems OK.
        delete = "30m"
      }
    }
    # The nodes running autoscaled nodes must be in a different fargate profile
    # than the node performing the autoscaling.  See
    # https://aws.github.io/aws-eks-best-practices/karpenter/#run-the-karpenter-controller-on-eks-fargate-or-on-a-worker-node-that-belongs-to-a-node-group
    karpenter = {
      name = "karpenter"
      selectors = [
        {
          namespace = "kube-system"
        },
        {
          namespace = "karpenter"
        }
      ]

      timeouts = {
        create = "20m"
        # For reasons unknown, Fargate profiles can take upward of 20 minutes to
        # delete! I've never seen them go past 30m, though, so this seems OK.
        delete = "30m"
      }
    }
  }

  # TODO: These rules are only needed for managed node groups.  Handle these
  # in the same way as the node groups themselves.
  # node_security_group_additional_rules = {
  #   ingress_self_all = {
  #     description = "Node to node all ports/protocols"
  #     protocol    = "-1"
  #     from_port   = 0
  #     to_port     = 0
  #     type        = "ingress"
  #     self        = true
  #   }
  #   # From https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/2462#issuecomment-1031624085
  #   ingress_allow_alb_controller_access_from_control_plane = {
  #     type                          = "ingress"
  #     protocol                      = "tcp"
  #     from_port                     = 9443
  #     to_port                       = 9443
  #     source_cluster_security_group = true
  #     description                   = "control plane to AWS load balancer controller"
  #   }
  #   ingress_allow_ingress_access_from_control_plane = {
  #     type                          = "ingress"
  #     protocol                      = "tcp"
  #     from_port                     = 8443
  #     to_port                       = 8443
  #     source_cluster_security_group = true
  #     description                   = "control plane to ingress nginx controller"
  #   }
  #   egress_all = {
  #     description      = "Node all egress"
  #     protocol         = "-1"
  #     from_port        = 0
  #     to_port          = 0
  #     type             = "egress"
  #     cidr_blocks      = ["0.0.0.0/0"]
  #     ipv6_cidr_blocks = ["::/0"]
  #   }
  # }

  # eks_managed_node_groups = {
  #   system = {
  #     launch_template_name = "${local.cluster_name}-lt"
  #     name                 = "${local.cluster_name}"
  #     subnet_ids           = var.single_az ? [module.vpc.private_subnets[0]] : module.vpc.private_subnets
  #     ami_id               = var.use_hardened_ami ? data.aws_ami.gsa-ise[0].id : null

  #     enable_bootstrap_user_data = var.use_hardened_ami ? true : false
  #     bootstrap_extra_args       = var.use_hardened_ami ? "--container-runtime dockerd" : ""
  #     pre_bootstrap_user_data    = !var.use_hardened_ami ? "" : <<-EOT
  #       export CONTAINER_RUNTIME="dockerd"
  #       export USE_MAX_PODS=false
  #     EOT

  #     # TODO: Update with gsa specific information
  #     # Reference: https://github.com/GSA/odp-jenkins-hardening-pipeline#bootscript
  #     # post_bootstrap_user_data = <<-EOT
  #     #   /build-artifacts/configure.sh <ELP-SERVER-NAME> <ELP-SERVER-PORT> <ENDGAME-API-TOKEN> <NESSUS-API-KEY> <NESSUS-SERVER> <NESSUS-PORT> <GSA_FISMA_System_ID> <GSA_Org_ID> <GSA_FCS_Tenant>
  #     # EOT

  #     block_device_mappings = {
  #       xvda = {
  #         device_name = "/dev/xvda"
  #         ebs = {
  #           volume_size           = 20
  #           encrypted             = true
  #           kms_key_id            = aws_kms_key.ebs-key.arn
  #           delete_on_termination = true
  #         }
  #       }
  #     }

  #     desired_size = var.mng_desired_capacity
  #     max_size     = var.mng_max_capacity
  #     min_size     = var.mng_min_capacity

  #     instance_types = var.mng_instance_types
  #     capacity_type  = "ON_DEMAND"
  #     tags           = { "aws-node-termination-handler/managed" = "true" }
  #   }
  # }

  cluster_timeouts = {
    # Default is 15m. Wait a little longer since MNGs take a while to delete.
    delete = "20m"
  }

}

# ---------------------------------------------
# ALL Policies for the pod execution IAM role
# ---------------------------------------------

# Policies that Terraform manages need to be attached to the generated IAM roles after cluster creation.
# Reference: https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest#%E2%84%B9%EF%B8%8F-error-invalid-for_each-argument-
resource "aws_iam_role_policy_attachment" "pod-logging" {
  for_each = merge(
    # module.eks.eks_managed_node_groups,
    module.eks.fargate_profiles,
  )

  policy_arn = aws_iam_policy.pod-logging.arn
  role       = each.value.iam_role_name
}

# resource "aws_iam_role_policy_attachment" "ebs-usage" {
#   for_each = merge(
#     # module.eks.eks_managed_node_groups,
#     module.eks.fargate_profiles,
#   )
# 
#   policy_arn = aws_iam_policy.ebs-usage.arn
#   role       = each.value.iam_role_name
# }

# TODO: SSM is only to scan managed node groups.  If we get to unify
# everything, these should be conditionally created if there are managed
# nodes.
# data "aws_iam_policy" "ssm_managed_instance" {
#   arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
# }
# 
# resource "aws_iam_role_policy_attachment" "karpenter_ssm_policy" {
#   role       = module.eks.cluster_iam_role_name
#   policy_arn = data.aws_iam_policy.ssm_managed_instance.arn
# }
# 

resource "aws_iam_role_policy_attachment" "ssm-usage" {
  for_each = merge(
    # module.eks.eks_managed_node_groups,
    module.eks.fargate_profiles,
  )

  policy_arn = aws_iam_policy.ssm-access-policy.arn
  role       = each.value.iam_role_name
}

resource "aws_iam_policy" "ssm-access-policy" {
  name        = "${local.cluster_name}-ssm-policy"
  path        = "/"
  description = "Policy and roles to permit SSM access / actions on EC2 instances, and to allow them to send metrics and logs to CloudWatch"

  policy = data.aws_iam_policy_document.ssm_access_role_policy.json
}

data "aws_iam_policy_document" "ssm_access_role_policy" {
  statement {
    sid = "SSMCoreAccess"
    actions = [
      "ssm:DescribeAssociation",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:GetDocument",
      "ssm:DescribeDocument",
      "ssm:GetManifest",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:ListAssociations",
      "ssm:ListInstanceAssociations",
      "ssm:PutInventory",
      "ssm:PutComplianceItems",
      "ssm:PutConfigurePackageResult",
      "ssm:UpdateAssociationStatus",
      "ssm:UpdateInstanceAssociationStatus",
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]

    resources = [
      "*",
    ]
  }
  statement {
    sid = "CloudWatchAgentAccess"
    actions = [
      "cloudwatch:PutMetricData",
      "ec2:DescribeVolumes",
      "ec2:DescribeTags",
    ]

    resources = [
      "*",
    ]
  }
  statement {
    sid = "CloudWatchLogsAccess"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]

    resources = [
      "*"
    ]
  }
}

# ---------------------------------------------
# Logging Policy for the pod execution IAM role
# ---------------------------------------------
resource "aws_iam_policy" "pod-logging" {
  name   = "${local.cluster_name}-pod-logging"
  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:CreateLogGroup",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }]
  }
  EOF
}


# Generate a kubeconfig file for use in provisioners
data "template_file" "kubeconfig" {
  template = <<-EOF
    apiVersion: v1
    kind: Config
    current-context: terraform
    clusters:
    - name: ${module.eks.cluster_arn}
      cluster:
        certificate-authority-data: ${module.eks.cluster_certificate_authority_data}
        server: ${module.eks.cluster_endpoint}
    contexts:
    - name: terraform
      context:
        cluster: ${module.eks.cluster_arn}
        user: terraform
    users:
    - name: terraform
      user:
        exec:
          apiVersion: client.authentication.k8s.io/v1beta1
          command: aws
          args:
            - "--region"
            - "${data.aws_region.current.name}"
            - "eks"
            - "get-token"
            - "--cluster-name"
            - "${module.eks.cluster_name}"
  EOF
}

resource "local_sensitive_file" "kubeconfig" {
  # Only create the file if requested; it's not needed by provisioners
  count           = var.write_kubeconfig ? 1 : 0
  content         = data.template_file.kubeconfig.rendered
  filename        = local.kubeconfig_name
  file_permission = "0600"
}


# We use this null_resource to ensure that the Kubernetes and helm providers are not
# actually exercised before the cluster is fully available. This averts
# race-cases between the kubernetes provider and the aws provider as a general
# class of problem.
resource "null_resource" "cluster-functional" {

  depends_on = [
    null_resource.prerequisite_binaries_present,
    module.eks,
    module.vpc,
    module.eks.fargate_profiles
    # We could include module.eks.fargate_profiles here, but realistically
    # Fargate doesn't have to be ready as long as the node group is ready.
  ]
}

# TODO: Document this properly
# I think this is used for k8s/helm configuration
# module.eks doesn't have a token by default and maybe this is the best way
# of doing this.  Just needs investigation
data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
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
