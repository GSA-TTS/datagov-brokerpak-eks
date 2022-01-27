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

  k8s_csidriver = <<-EOF
  apiVersion: storage.k8s.io/v1beta1
  kind: CSIDriver
  metadata:
    name: efs.csi.aws.com
  spec:
    attachRequired: false
  EOF

  k8s_storageclass = <<-EOF
  kind: StorageClass
  apiVersion: storage.k8s.io/v1
  metadata:
    name: efs-sc
  provisioner: efs.csi.aws.com
  EOF

  k8s_pv = <<-EOF
  apiVersion: v1
  kind: PersistentVolume
  metadata:
    name: efs-pv
  spec:
    capacity:
      storage: 5Gi
    volumeMode: Filesystem
    accessModes:
      - ReadWriteOnce
    storageClassName: ""
    persistentVolumeReclaimPolicy: Retain
    csi:
      driver: efs.csi.aws.com
      volumeHandle: <efs-id>
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

resource "aws_efs_file_system" "eks_pv" {
  creation_token = "eks_pv"

  tags = {
    Name = "${local.cluster_name}-PV"
  }
}

resource "aws_efs_mount_target" "efs_vpc" {
  count = 3
  file_system_id = aws_efs_file_system.eks_pv.id
  subnet_id      = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs_mounts.id]
}

resource "aws_iam_role_policy" "efs-policy" {
  name_prefix = "${local.cluster_name}-efs-policy"
  role        = aws_iam_role.iam_role_fargate.name
  policy      = local.efs_policy
}

resource "null_resource" "setup_pv" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(module.eks.kubeconfig)
      DRIVER = "${local.k8s_csidriver}"
      STORAGECLASS = "${local.k8s_storageclass}"
      PV = replace("${local.k8s_pv}", "<efs-id>", aws_efs_file_system.eks_pv.id)
    }

    command = <<-EOF
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) apply -f - <<< "$DRIVER"
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) apply -f - <<< "$STORAGECLASS"
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) apply -f - <<< "$PV"
    EOF
  }
  depends_on = [
    null_resource.cluster-functional,
    aws_efs_file_system.eks_pv,
    aws_efs_mount_target.efs_vpc,
    aws_security_group.efs_mounts
  ]
}
