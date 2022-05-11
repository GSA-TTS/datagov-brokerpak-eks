locals {
  cluster_name    = "k8s-${substr(sha256(var.instance_name), 0, 16)}"
  cluster_version = "1.21"
  kubeconfig_name = "kubeconfig-${local.cluster_name}"
}

data "aws_ami" "gsa-ise" {
  owners      = ["self", "752281881774", "821341638715"]
  most_recent = true
  filter {
    name   = "name"
    values = ["ISE-AMZ-LINUX-EKS-v1.21-GSA-HARDENED*"]
  }
}

module "eks" {
  source                                 = "terraform-aws-modules/eks/aws"
  version                                = "~> 18.20.1"
  cluster_name                           = local.cluster_name
  cluster_version                        = local.cluster_version
  vpc_id                                 = module.vpc.vpc_id
  subnet_ids                             = module.vpc.private_subnets
  cluster_enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = 180
  enable_irsa                            = true
  cluster_endpoint_private_access        = true
  cluster_endpoint_public_access_cidrs = concat(
    var.control_plane_ingress_cidrs,       # User-specified IP
    ["${module.vpc.nat_public_ips[0]}/32", # EKS Cluster Public IP
    "142.4.160.56/29", "15.220.252.0/22", "54.148.0.0/15", "99.77.130.0/24", "99.150.56.0/21", "15.220.207.0/24", "15.193.7.0/24", "18.236.0.0/15", "161.188.148.0/23", "54.200.0.0/15", "64.252.72.0/24", "3.4.3.0/24", "52.94.249.64/28", "161.188.156.0/23", "15.181.253.0/24", "70.224.192.0/18", "54.245.0.0/16", "99.77.152.0/24", "35.160.0.0/13", "54.68.0.0/14", "54.212.0.0/15", "15.220.202.0/23", "142.4.160.64/29", "52.95.230.0/24", "99.77.253.0/24", "3.4.6.0/24", "15.220.208.128/26", "35.80.0.0/12", "15.220.200.0/23", "52.12.0.0/15", "52.75.0.0/16", "54.218.0.0/16", "3.5.76.0/22", "15.181.0.0/20", "54.244.0.0/16", "44.224.0.0/11", "64.252.73.0/24", "52.95.255.112/28", "100.20.0.0/14", "15.220.0.0/20", "15.220.16.0/20", "161.188.134.0/23", "54.214.0.0/16", "34.208.0.0/12", "35.71.64.0/22", "18.34.244.0/22", "52.36.0.0/14", "15.220.226.0/24", "54.202.0.0/15", "15.181.128.0/20", "15.220.204.0/24", "15.181.245.0/24", "52.95.247.0/24", "50.112.0.0/16", "15.181.64.0/20", "142.4.160.16/29", "52.94.116.0/22", "15.181.248.0/24", "15.253.0.0/16", "15.181.252.0/24", "52.46.180.0/22", "18.34.48.0/20", "15.181.16.0/20", "162.222.148.0/22", "52.24.0.0/14", "64.252.65.0/24", "18.246.0.0/16", "3.5.80.0/21", "161.188.138.0/23", "15.220.205.0/24", "52.88.0.0/15", "142.4.160.104/29", "15.220.206.0/24", "161.188.152.0/23", "15.177.80.0/24", "15.254.0.0/16", "52.40.0.0/14", "64.252.70.0/24", "52.32.0.0/14", "54.184.0.0/13", "142.4.160.96/29", "15.181.251.0/24", "142.4.160.32/29", "161.188.160.0/23", "64.252.71.0/24", "35.155.0.0/16", "52.10.0.0/15", "3.4.4.0/24", "15.181.116.0/22", "15.220.224.0/23", "15.181.250.0/24", "52.94.248.96/28", "99.77.186.0/24", "18.237.140.160/29" # AWS EC2 IPs in the us-west-2 region :(
    ]
  )
  tags = merge(var.labels,
    { "domain" = local.domain },
    { "karpenter.sh/discovery" = local.cluster_name }
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
    system = {
      launch_template_name = "${local.cluster_name}-lt"
      name                 = "${local.cluster_name}"
      ami_id               = data.aws_ami.gsa-ise.id
      subnet_ids           = var.single_az ? [module.vpc.private_subnets[0]] : module.vpc.private_subnets

      enable_bootstrap_user_data = true
      bootstrap_extra_args       = "--container-runtime dockerd"
      pre_bootstrap_user_data    = <<-EOT
        export CONTAINER_RUNTIME="dockerd"
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
      tags           = { "aws-node-termination-handler/managed" = "true" }
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
}

data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_id
}

data "aws_launch_template" "eks_launch_template" {
  id = module.eks.eks_managed_node_groups["system"].launch_template_id
}
