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
    description      = "NFS Traffic from Fargate"
    from_port        = 2049
    to_port          = 2049
    protocol         = "tcp"
    cidr_blocks      = module.vpc.private_subnets_cidr_blocks
  }

  tags = {
    Name = "allow_nfs_for_efs"
  }
}

resource "aws_efs_file_system" "solrcloud_pv" {
  creation_token = "solrcloud_pv"

  tags = {
    Name = "MyProduct"
  }
}

resource "aws_efs_mount_target" "efs_vpc" {
  count = 3
  file_system_id = aws_efs_file_system.solrcloud_pv.id
  subnet_id      = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs_mounts.id]
}

resource "aws_iam_role_policy" "efs-policy" {
  name_prefix = "${local.cluster_name}-efs-policy"
  role        = aws_iam_role.iam_role_fargate.name
  policy      = local.efs_policy
}
