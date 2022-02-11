locals {
  ebs_key_policy = <<-POLICY
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "AWS": "*"
        },
        "Action": "kms:*",
        "Resource": "*"
      }
    ]
  }
  POLICY

  ebs_policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ec2:CreateSnapshot",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:ModifyVolume",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:CreateTags"
        ],
        "Resource": [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ],
        "Condition": {
          "StringEquals": {
            "ec2:CreateAction": [
              "CreateVolume",
              "CreateSnapshot"
            ]
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DeleteTags"
        ],
        "Resource": [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:CreateVolume"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "aws:RequestTag/ebs.csi.aws.com/cluster": "true"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:CreateVolume"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "aws:RequestTag/CSIVolumeName": "*"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:CreateVolume"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "aws:RequestTag/kubernetes.io/cluster/*": "owned"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DeleteVolume"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "ec2:ResourceTag/ebs.csi.aws.com/cluster": "true"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DeleteVolume"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "ec2:ResourceTag/CSIVolumeName": "*"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DeleteVolume"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "ec2:ResourceTag/kubernetes.io/cluster/*": "owned"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DeleteSnapshot"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "ec2:ResourceTag/CSIVolumeSnapshotName": "*"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DeleteSnapshot"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "ec2:ResourceTag/ebs.csi.aws.com/cluster": "true"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ],
        "Resource": ["<custom-key-id>"],
        "Condition": {
          "Bool": {
            "kms:GrantIsForAWSResource": "true"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:GenerateDataKeyWithoutPlaintext"
        ],
        "Resource": ["<custom-key-id>"]
      }
    ]
  }
  EOF
}

# Default KMS Key Delegation is not enough since it restricts
# the 'Pricipal' to only the root account.
# This policy allows the EBS addon to create additional keys
# for each new EBS volume based on this root key.
resource "aws_kms_key" "ebs-key" {
  description             = "${local.cluster_name}-ebs-key"
  deletion_window_in_days = 7
  policy                  = local.ebs_key_policy
}

resource "aws_iam_role_policy" "ebs-policy" {
  name_prefix = "${local.cluster_name}-ebs-policy"
  role        = aws_iam_role.iam_role_fargate.name
  policy      = replace(local.ebs_policy, "<custom-key-id>", aws_kms_key.ebs-key.arn)
}

resource "aws_eks_addon" "ebs-csi" {
  cluster_name = module.eks.cluster_id
  addon_name   = "aws-ebs-csi-driver"
}

resource "kubernetes_storage_class" "ebs-sc" {
  metadata {
    name = "ebs-sc"
  }
  parameters = {
    encrypted = "true"
    kmsKeyId  = aws_kms_key.ebs-key.key_id
  }
  # Storage provisioner retrieved from
  # https://docs.aws.amazon.com/eks/latest/userguide/storage-classes.html
  storage_provisioner    = "kubernetes.io/aws-ebs"
  allow_volume_expansion = true
}
