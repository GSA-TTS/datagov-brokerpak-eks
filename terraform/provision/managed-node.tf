# resource "aws_eks_node_group" "cluster-cni" {
#   cluster_name    = module.eks.cluster_id
#   node_group_name = "cni-group"
#   node_role_arn   = aws_iam_role.cni.arn
#   subnet_ids      = module.vpc.public_subnets
# 
#   scaling_config {
#     desired_size = 1
#     max_size     = 1
#     min_size     = 1
#   }
# 
#   update_config {
#     max_unavailable = 1
#   }
# 
#   # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
#   # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
#   depends_on = [
#     aws_iam_role_policy_attachment.cni-AmazonEKSWorkerNodePolicy,
#     aws_iam_role_policy_attachment.cni-AmazonEKS_CNI_Policy,
#     aws_iam_role_policy_attachment.cni-AmazonEC2ContainerRegistryReadOnly,
#   ]
# }

resource "aws_iam_role" "cni" {
  name = "eks-node-group-cni"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "cni-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.cni.name
}

resource "aws_iam_role_policy_attachment" "cni-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.cni.name
}

resource "aws_iam_role_policy_attachment" "cni-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.cni.name
}

# ----

resource "aws_eks_addon" "cni" {
    cluster_name = module.eks.cluster_id
    addon_name   = "vpc-cni"
}

data "tls_certificate" "eks-cni" {
  url = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "cni_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-node"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "cni-2" {
  assume_role_policy = data.aws_iam_policy_document.cni_assume_role_policy.json
  name               = "vpc-cni-role"
}

resource "aws_iam_role_policy_attachment" "cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.cni-2.name
}
