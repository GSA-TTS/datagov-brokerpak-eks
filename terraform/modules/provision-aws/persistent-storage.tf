
# TODO: This file blanket replaced EBS with EFS again.  If we want to
# support both... OR if we need EBS for managed node groups.. this file
# would need to change

locals {
  efs_policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "elasticfilesystem:CreateAccessPoint"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "aws:RequestTag/efs.csi.aws.com/cluster": "true"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": "elasticfilesystem:DeleteAccessPoint",
        "Resource": "*",
        "Condition": {
          "StringEquals": {
            "aws:ResourceTag/efs.csi.aws.com/cluster": "true"
          }
        }
      }
    ]
  }
  EOF
}

resource "aws_security_group" "efs_mounts" {
  name        = "efs_mounts"
  description = "Mound EFS Volume in all pods w/i Fargate"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "NFS Traffic from Fargate"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
  }

  tags = {
    Name = "allow_nfs_for_efs"
  }
}

resource "aws_efs_file_system" "eks_efs" {
  creation_token = "${local.cluster_name}-PV"

  # encryption-at-rest
  encrypted = true
  tags = {
    Name = "${local.cluster_name}-PV"
  }
}

resource "aws_efs_file_system_policy" "policy" {
  file_system_id = aws_efs_file_system.eks_efs.id

  # encryption-in-transit
  policy = <<-POLICY
  {
    "Version": "2012-10-17",
    "Id": "${local.cluster_name}-efs-policy",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "AWS": "*"
        },
        "Action": [
          "elasticfilesystem:ClientRootAccess",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientMount"
        ],
        "Condition": {
          "Bool": {
            "elasticfilesystem:AccessedViaMountTarget": "true"
          }
        }
      },
      {
        "Effect": "Deny",
        "Principal": {
          "AWS": "*"
        },
        "Action": "*",
        "Condition": {
          "Bool": {
            "aws:SecureTransport": "false"
          }
        }
      }
    ]
  }
  POLICY
}

resource "aws_efs_mount_target" "efs_vpc" {
  count           = 3
  file_system_id  = aws_efs_file_system.eks_efs.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs_mounts.id]
}

resource "aws_iam_role_policy" "efs-policy" {
  name_prefix = "${local.cluster_name}-efs-policy"
  role        = aws_iam_role.iam_role_fargate.name
  policy      = local.efs_policy
}

# This isn't used for Fargate workloads, since they cannot dynamically provision
# volumes:
# https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html#:~:text=Considerations
# However, we're leaving it here so that non-Fargate workloads can
# still dynamically provision EFS volumes if they want to.
resource "kubernetes_storage_class" "efs-sc" {
  metadata {
    name = "efs-sc"
  }
  storage_provisioner    = "efs.csi.aws.com"
  allow_volume_expansion = true
}

resource "kubernetes_persistent_volume" "pv" {
  metadata {
    name = "pv"
  }
  spec {
    capacity = {
      storage = "5Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    storage_class_name               = ""
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      csi {
        driver        = "efs.csi.aws.com"
        volume_handle = aws_efs_file_system.eks_efs.id
      }
    }
  }
}

