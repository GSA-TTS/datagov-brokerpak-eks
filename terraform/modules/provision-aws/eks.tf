locals {
  cluster_name    = "k8s-${substr(sha256(var.instance_name), 0, 16)}"
  cluster_version = "1.21"
  kubeconfig      = "kubeconfig-${local.cluster_name}"
}

data "aws_ami" "gsa-ise" {
  owners      = ["self", "752281881774"]
  most_recent = true
  filter {
    name   = "name"
    values = ["ISE-AMZ-LINUX-EKS-v1.21-GSA-HARDENED*"]
  }
}

module "eks" {
  source                                 = "terraform-aws-modules/eks/aws"
  version                                = "~> 18.6"
  cluster_name                           = local.cluster_name
  cluster_version                        = local.cluster_version
  vpc_id                                 = module.vpc.vpc_id
  subnet_ids                             = module.vpc.private_subnets
  cluster_enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = 180
  tags                                   = merge(var.labels, { "domain" = local.domain })
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

  # fargate_profiles = {
  #   default = {
  #     name = "default"
  #     selectors = [
  #       {
  #         namespace = "kube-system"
  #       },
  #       {
  #         namespace = "default"
  #       }
  #     ]

  #     timeouts = {
  #       create = "20m"
  #       # For reasons unknown, Fargate profiles can take upward of 20 minutes to
  #       # delete! I've never seen them go past 30m, though, so this seems OK.
  #       delete = "30m"
  #     }
  #   }
  # }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # From https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/2462#issuecomment-1031624085
    ingress_allow_alb_controller_access_from_control_plane = {
      type                          = "ingress"
      protocol                      = "tcp"
      from_port                     = 9443
      to_port                       = 9443
      source_cluster_security_group = true
      description                   = "control plane to AWS load balancer controller"
    }
    ingress_allow_ingress_access_from_control_plane = {
      type                          = "ingress"
      protocol                      = "tcp"
      from_port                     = 8443
      to_port                       = 8443
      source_cluster_security_group = true
      description                   = "control plane to ingress nginx controller"
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  eks_managed_node_groups = {
    system_node_group = {
      launch_template_name = ""
      name                 = "mng-${substr(local.cluster_name, 4, 24)}"
      ami_id               = data.aws_ami.gsa-ise.id

      enable_bootstrap_user_data = true
      bootstrap_extra_args       = "--container-runtime containerd --kubelet-extra-args '--max-pods=20'"
      pre_bootstrap_user_data    = <<-EOT
        export CONTAINER_RUNTIME="containerd"
        export USE_MAX_PODS=false
      EOT

      # TODO: Update with gsa specific information
      # Reference: https://github.com/GSA/odp-jenkins-hardening-pipeline#bootscript
      # post_bootstrap_user_data = <<-EOT
      #   /build-artifacts/configure.sh <ELP-SERVER-NAME> <ELP-SERVER-PORT> <ENDGAME-API-TOKEN> <NESSUS-API-KEY> <NESSUS-SERVER> <NESSUS-PORT> <GSA_FISMA_System_ID> <GSA_Org_ID> <GSA_FCS_Tenant>
      # EOT

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            encrypted             = true
            kms_key_id            = aws_kms_key.ebs-key.arn
            delete_on_termination = true
          }
        }
      }

      desired_size = var.mng_desired_capacity
      max_size     = var.mng_max_capacity
      min_size     = var.mng_min_capacity

      instance_types = var.mng_instance_types
      capacity_type  = "ON_DEMAND"
    }
  }

  cluster_timeouts = {
    # Default is 15m. Wait a little longer since MNGs take a while to delete.
    delete = "20m"
  }

}

# Policies that Terraform manages need to be attached to the generated IAM roles after cluster creation.
# Reference: https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest#%E2%84%B9%EF%B8%8F-error-invalid-for_each-argument-
resource "aws_iam_role_policy_attachment" "pod-logging" {
  for_each = merge(
    module.eks.eks_managed_node_groups,
    module.eks.fargate_profiles,
  )

  policy_arn = aws_iam_policy.pod-logging.arn
  role       = each.value.iam_role_name
}

resource "aws_iam_role_policy_attachment" "ebs-usage" {
  for_each = merge(
    module.eks.eks_managed_node_groups,
    module.eks.fargate_profiles,
  )

  policy_arn = aws_iam_policy.ebs-usage.arn
  role       = each.value.iam_role_name
}

resource "aws_iam_role_policy_attachment" "ssm-usage" {
  for_each = merge(
    module.eks.eks_managed_node_groups,
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
        exec:
          apiVersion: client.authentication.k8s.io/v1alpha1
          command: aws-iam-authenticator
          args:
            - "token"
            - "-i"
            - "${data.aws_eks_cluster.main.name}"
  EOF
}

resource "local_file" "kubeconfig" {
  # Only create the file if requested; it's not needed by provisioners
  count             = var.write_kubeconfig ? 1 : 0
  sensitive_content = data.template_file.kubeconfig.rendered
  filename          = local.kubeconfig
  file_permission   = "0600"
}


# We use this null_resource to ensure that the Kubernetes and helm providers are not
# actually exercised before the cluster is fully available. This averts
# race-cases between the kubernetes provider and the aws provider as a general
# class of problem.
resource "null_resource" "cluster-functional" {

  depends_on = [
    null_resource.prerequisite_binaries_present,
    module.eks.cluster_id,
    module.eks.eks_managed_node_groups,
    module.eks.aws_eks_addon,
    module.eks,
    module.vpc
    # We could include module.eks.fargate_profiles here, but realistically
    # Fargate doesn't have to be ready as long as the node group is ready.
  ]
}

# The kubernetes provider and any resources that need to actually interact with
# Kubernetes make use of these data sources so they won't be instantiated before
# the cluster is ready for business.
data "aws_eks_cluster" "main" {
  name = module.eks.cluster_id
  depends_on = [
    null_resource.cluster-functional
  ]
}

data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_id
  depends_on = [
    null_resource.cluster-functional
  ]
}
